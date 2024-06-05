/* stream_test.c
 *
 * Test reading  from FT2232H in synchronous FIFO mode.
 *
 * The FT2232H must supply data due to an appropriate circuit
 *
 * To check for skipped block with appended code, 
 *     a structure as follows is assumed
 * 1* uint32_t num (incremented in 0x4000 steps)
 * 3* uint32_t dont_care
 *
 * After start, data will be read in streaming until the program is aborted
 * Progress information will be printed out
 * If a filename is given on the command line, the data read will be
 * written to that file
 *
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <signal.h>
#include <errno.h>
#include <ftdi.h>
#include <fftw3.h>
#include <pthread.h>
#include <semaphore.h> 
#include <math.h>
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <float.h>

const double SWEEPTIME = 0.001039;
const double BANDWIDTH =  100000000;
const double SLOPE = BANDWIDTH / SWEEPTIME;
const double C = 299792458;

#define SAMPLING_RATE 1800000

const double WAVELENGTH = 0.1224;

//Axes
#define YMINOR 5
#define YMAJOR 20

#define XMINOR 50
#define XMAJOR 200

//FFT array size
#define FFTSIZE 2100
#define TIMESIZE 512

//Pixels per FFT bin
#define PXTIME 1
#define PXFFT 1

//FFT screen zoom
#define XZOOM 1
#define YZOOM 1

#define ZEROSAMPLES 0 //Discard the first this many samples

#define DISTOFFSET 0

//Minimum and maximum samples
#define MINSAMPLES 1800
#define MAXSAMPLES 1850


const int WIDTH = FFTSIZE * PXFFT / 2;
const int HEIGHT = TIMESIZE * PXTIME; 

double fft_in[TIMESIZE][FFTSIZE][2];
double fft_out[TIMESIZE][FFTSIZE][2];

double hann[TIMESIZE][FFTSIZE];


SDL_Event event;
SDL_Renderer * renderer;
SDL_Window * window;

sem_t fft_mutex;

fftw_complex * in;
fftw_complex * out;
fftw_plan p;

int row = 0;
int col = 0;
int firstPacket = 1;

int initSDL = 1;

static int exitRequested = 0;
/*
 * sigintHandler --
 *
 *    SIGINT handler, so we can gracefully exit when the user hits ctrl-C.
 */

static void sigintHandler(int signum)
{
   exitRequested = 1;
}

int distanceToX(double distance){
	distance -= DISTOFFSET;
	double frequency = SLOPE * 2 * distance / C;	
	double fftbin = frequency  / ( SAMPLING_RATE / FFTSIZE);
	fftbin *= PXFFT * XZOOM;
	return (int)(fftbin);
}

int velocityToY(double velocity){
	double mid = HEIGHT / 2.0;
	double velRes = WAVELENGTH / ( 2 * SWEEPTIME * TIMESIZE );
    double bin = velocity / velRes;
	bin *= PXTIME * YZOOM;
	return (int)(bin + mid);	
}

struct RGB {
    unsigned char R;
    unsigned char G;
    unsigned char B;
};

struct HSV {
    double H;
    double S;
    double V;
};

struct RGB HSVToRGB(struct HSV hsv) {
    double r = 0, g = 0, b = 0;

    if (hsv.S == 0) {
        r = hsv.V;
        g = hsv.V;
        b = hsv.V;
    } else {
        int i;
        double f, p, q, t;

        if (hsv.H == 360)
            hsv.H = 0;
        else
            hsv.H = hsv.H / 60;

        i = (int) trunc(hsv.H);
        f = hsv.H - i;

        p = hsv.V * (1.0 - hsv.S);
        q = hsv.V * (1.0 - (hsv.S * f));
        t = hsv.V * (1.0 - (hsv.S * (1.0 - f)));

        switch (i) {
        case 0:
            r = hsv.V;
            g = t;
            b = p;
            break;

        case 1:
            r = q;
            g = hsv.V;
            b = p;
            break;

        case 2:
            r = p;
            g = hsv.V;
            b = t;
            break;

        case 3:
            r = p;
            g = q;
            b = hsv.V;
            break;

        case 4:
            r = t;
            g = p;
            b = hsv.V;
            break;

        default:
            r = hsv.V;
            g = p;
            b = q;
            break;
        }

    }

    struct RGB rgb;
    rgb.R = r * 255;
    rgb.G = g * 255;
    rgb.B = b * 255;

    return rgb;
}

void convertToMagSq(double x[TIMESIZE][FFTSIZE][2]) {
    for (int i = 0; i < TIMESIZE; i++) {
        for (int j = 0; j < FFTSIZE; j++) {
            x[i][j][0] = 20 * log10(x[i][j][0] * x[i][j][0] + x[i][j][1] * x[i][j][1]);
        }
    }
}

double map(double x, double in_min, double in_max, double out_min, double out_max) {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

void window1d(double x[], int N) {
    for (int i = 0; i < N; i++) {
        double u = sin(M_PI * i / (N - 1));
        x[i] = u * u;
    }
}

void window2d(double x[TIMESIZE][FFTSIZE]) {
    double col[FFTSIZE];
    double row[TIMESIZE];
    window1d(row, TIMESIZE);
    window1d(col, FFTSIZE);
    for (int i = 0; i < TIMESIZE; i++) {
        for (int j = 0; j < FFTSIZE; j++) {
            x[i][j] = row[i] * col[j];
        }
    }
}

void setRenderColor(double hue){
            	        double value = 1;
	        double saturation = 1;
                //Bound numbers which are too large
	        hue = hue < -45? -45:hue;
	        hue = hue > 315 ? 315:hue;

            //Higher numbers -> white
	        if (hue < 0){
		        saturation = map(hue, -45, 0, 0.001, 1);
		        hue = 0;
	        }

            //Lower numbers -> black
	        if (hue > 270){
		        value = map(hue, 270, 315, 1, 0.001);
		        hue = 270;
	        }
    
            //Set color
            struct HSV hsvcolor = {hue, saturation, value};
            struct RGB rgbcolor = HSVToRGB(hsvcolor);
            if (SDL_SetRenderDrawColor(renderer, rgbcolor.R, rgbcolor.G, rgbcolor.B, 255)){
                fprintf(stderr, "Setting color failed: %s", SDL_GetError());
            }
}
void drawSmallText(int x, int y, char* text, bool centered){
	const int size = 15;
	TTF_Font* font = TTF_OpenFont("ComicNeue-Regular.ttf", size);
	SDL_Color foregroundColor = {255, 255, 255};
	SDL_Surface* textSurface = TTF_RenderText_Solid(font, text, foregroundColor);
    SDL_Texture * texture = SDL_CreateTextureFromSurface(renderer, textSurface);
	
	int texW = 0;
	int texH = 0;
	SDL_QueryTexture(texture, NULL, NULL, &texW, &texH);
	SDL_Rect dstrect = {centered?x - texW / 2:x,  y - texH / 2, texW, texH};
	SDL_RenderCopy(renderer, texture, NULL, &dstrect);
	SDL_RenderPresent(renderer);

	SDL_DestroyTexture(texture);
	SDL_FreeSurface(textSurface);
	TTF_CloseFont(font);
}
void drawToScreen(double x[TIMESIZE][FFTSIZE][2]) {
    double avg[FFTSIZE / 2] = {0};
    double max[FFTSIZE / 2] = {-99999};
    for (int i = 0; i < TIMESIZE; i++) {
        for (int j = 0; j < FFTSIZE; j++) {
            double value = x[i][j][0];
            avg[0] += value;
            max[0] = max[0] < value ? value : max[0];
        }
    }
  //  for (int i = 0; i < FFTSIZE/2; i++){
        avg[0] /= TIMESIZE;
  //  }
        avg[0] /= (FFTSIZE);
    

    //FFT Shift
    for (int i = -TIMESIZE / 2 / YZOOM; i < TIMESIZE / 2 / YZOOM ; i++) {
        for (int m = 0; m < FFTSIZE / 2 / XZOOM; m++) {

            //Wrap i around (basically implement fftshift for time axis)
            int j = i >= 0 ? i : TIMESIZE + i;

            //Map the value linearly between the average and maximum for a column
            double hue = map(x[j][m][0], avg[0]-20, max[0], 315, -45);
            //printf("%ld\n", hue);


            setRenderColor(hue);

            //Remap i to physical pixel location
	        j = i >= 0 ? i : TIMESIZE  / YZOOM + i ;
            int height = j <= TIMESIZE / (2 * YZOOM) ? TIMESIZE /(2 * YZOOM) - j : TIMESIZE * 3 / (2 * YZOOM) - j;
            height *= PXTIME * YZOOM;
	        int width = m * PXFFT * XZOOM;
            SDL_Rect rect = {.x = width, .y = height, .w = PXFFT * XZOOM, .h = PXTIME * YZOOM};
            SDL_RenderFillRect(renderer, &rect);
           //     fprintf(stderr, "Drawing rect failed: %s", SDL_GetError());
          //  }
            // SDL_RenderDrawPoint(renderer, width, height );

        }
    }
    //draw legend
    SDL_SetRenderDrawColor(renderer, 50, 50, 50, 255);
    SDL_Rect rect = {.x = WIDTH, .y = 0, .w = 200, .h = HEIGHT};
    SDL_RenderFillRect(renderer, &rect);
    for (int i = 0; i < 16; i++){
        double hue = i * 22.5 - 45;
        double val = map(hue, 315, -45, avg[0], max[0]);
        setRenderColor(hue);
        SDL_Rect rect = {.x = WIDTH + 10, .y = 20 * i, .w = 50, .h = 20};
        SDL_RenderFillRect(renderer, &rect);
        char buf[20];
        sprintf(buf, "%.1f dB", val);
        drawSmallText(WIDTH + 65, 20 * i+8, buf, false);

    }

    SDL_RenderPresent(renderer);
}

void drawHorizLine(int y){
	SDL_SetRenderDrawColor(renderer, 255, 255, 255, 128);
	SDL_RenderDrawLine(renderer, 0, y, WIDTH, y); 
}

void drawVertLine(int x){
	SDL_SetRenderDrawColor(renderer, 255, 255, 255, 128);
	SDL_RenderDrawLine(renderer, x, 0, x, HEIGHT);
}

void drawText(int x, int y, char* text, bool centered){
	const int size = 30;
	TTF_Font* font = TTF_OpenFont("ComicNeue-Regular.ttf", size);
	SDL_Color foregroundColor = {255, 255, 255};
	SDL_Surface* textSurface = TTF_RenderText_Solid(font, text, foregroundColor);
    SDL_Texture * texture = SDL_CreateTextureFromSurface(renderer, textSurface);
	
	int texW = 0;
	int texH = 0;
	SDL_QueryTexture(texture, NULL, NULL, &texW, &texH);
	SDL_Rect dstrect = {centered?x - texW / 2:x,  y - texH / 2, texW, texH};
	SDL_RenderCopy(renderer, texture, NULL, &dstrect);
	SDL_RenderPresent(renderer);

	SDL_DestroyTexture(texture);
	SDL_FreeSurface(textSurface);
	TTF_CloseFont(font);
}

void drawGridAndLabels(){
	double poscounter = 0;
	
	while (distanceToX(poscounter) < WIDTH){
		drawVertLine(distanceToX(poscounter));
		poscounter += XMINOR;
	}

	drawHorizLine(HEIGHT / 2);
	double velcounter = YMINOR;

	while (velocityToY(velcounter) < HEIGHT ){
		drawHorizLine(velocityToY(velcounter));
		drawHorizLine(HEIGHT - velocityToY(velcounter));
		velcounter += YMINOR;
	}

	double labelpos = XMAJOR;
	double labelvel = YMAJOR;
	while (distanceToX(labelpos) < WIDTH){
		char label[100];
		sprintf(label, "%.0f m", labelpos);
		drawText( distanceToX(labelpos) , HEIGHT - 20, label, true);
		labelpos += XMAJOR;
	}	

	drawText(20, HEIGHT / 2, "0 m/s", false);
	while (velocityToY(labelvel) < HEIGHT){
		char label1[100];
		char label2[100];
		sprintf(label1, "%.1f m/s", labelvel);
		sprintf(label2, "-%.1f m/s", labelvel);
		drawText (10, HEIGHT - velocityToY(labelvel), label1, false);
		drawText (10, velocityToY(labelvel), label2, false);
		labelvel += YMAJOR;
	}
            printf("%s, %s \n", SDL_GetError(), TTF_GetError());

}

int samples_i [TIMESIZE][FFTSIZE];
int samples_q [TIMESIZE][FFTSIZE];
int offset = 0;
int overload = 0;

static int
readCallback(uint8_t *buffer, int length, FTDIProgressInfo *progress, void *userdata)
{
    if (col + length / 8 >= FFTSIZE){
        fprintf(stderr, "Array out of bounds: readCallback \n");
        return -69;
    }
    if (offset == 2){
        samples_q[row][col] = (int16_t)(buffer[0] << 8 | buffer[1]);
        col++;
    }
    for (int i = firstPacket ? ZEROSAMPLES * 8 : (8 - offset) % 8; i<length - 7; i+=8){
        samples_i[row][col] = (int16_t)(buffer[i] << 8 | buffer[i+1]);
        samples_q[row][col] = (int16_t)(buffer[i+2] << 8 | buffer[i+3]);
        col++;
    }
    
    offset += length;
    offset %= 8;

    if (offset == 2){
        samples_i[row][col] = (int16_t)(buffer[length-2] << 8 | buffer[length-1]);
    }

    if (offset == 4){
        samples_i[row][col] = (int16_t)(buffer[length-4] << 8 | buffer[length-3]);
        samples_q[row][col] = (int16_t)(buffer[length-2] << 8 | buffer[length-1]);
        col++;
    }
    
    if (offset == 6){
        samples_i[row][col] = (int16_t)(buffer[length-6] << 8 | buffer[length-5]);
        samples_q[row][col] = (int16_t)(buffer[length-4] << 8 | buffer[length-3]);
        col++;
    }

    if (length == 510){
        firstPacket = 0;
    }
    else if (!firstPacket || length > 0  ){
        if (col < MINSAMPLES){
            printf("Incomplete row detected...: size %d \n", col);
        }
        else{
        firstPacket = 1;
        row++;
        col = 0;
        offset = 0;
        }

    }
    if (row == TIMESIZE){
        //printf("Doing FFT...\n");
        double averages_i[TIMESIZE] = {0};
        double averages_q[TIMESIZE] = {0};

        for (int j = 0 ; j < TIMESIZE; j++){
            int sum_i = 0;
            int sum_q = 0;
            for (int k = 0 ; k < FFTSIZE ; k++){
                sum_i += samples_i[j][k];
                sum_q += samples_q[j][k];
                if (samples_i[j][k] == 32767 || samples_i[j][k] == -32768)
                    overload++;
                if (samples_q[j][k] == 32767 || samples_q[j][k] == -32768)
                    overload++;
            }
            averages_i[j] += sum_i;
            averages_q[j] += sum_q;
            
        }

        for (int k = 0; k < TIMESIZE; k++){
            averages_i[k] /= FFTSIZE;
            averages_q[k] /= FFTSIZE;
            
        }

        for (int j = 0; j < TIMESIZE; j++) {
            for (int k = 0; k < FFTSIZE; k++) {
				fft_in[j][k][0] = (samples_i[j][k] - averages_i[j]) * hann[j][k];
                fft_in[j][k][1] = (samples_q[j][k] - averages_q[j]) * hann[j][k];
            }
        }
        sem_post(&fft_mutex);
        memset(samples_i, 0, sizeof(samples_i));
        memset(samples_q, 0, sizeof(samples_q));
        if (overload > 0){
            printf("WARNING: ADC OVERLOAD ON %d SAMPLES. Consider reducing gain.", overload);
        }
        row = 0;
        overload = 0;
        
    }
    return exitRequested;
}

void SDL_setup(){
    SDL_Init(SDL_INIT_EVERYTHING);
    if(SDL_CreateWindowAndRenderer(WIDTH + 200, HEIGHT, 0, & window, & renderer)){
        fprintf(stderr, "Error creating window: %s", SDL_GetError());
    }
    SDL_SetWindowTitle( window, "Radar Range and Velocity Plot"); 
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    SDL_RenderClear(renderer);
    if(TTF_Init()){
        fprintf(stderr, "Error creating TTF: %s", TTF_GetError());
    }

    drawGridAndLabels();
}

void * fftCompute(void * arg) {
    while (true) {
        if (initSDL){
            initSDL = 0;
            SDL_setup();
        }
        //printf("fft thread waiting...\n");
        sem_wait(&fft_mutex);
        //printf("fft thread running ... \n");

        in = &fft_in;
        out = &fft_out;
        fftw_execute(p);
        convertToMagSq(fft_out);
        drawToScreen(fft_out);
        drawGridAndLabels();
   }
}


int main(int argc, char **argv)
{
    window2d(hann);
    printf("Hann window created\n");
    if(sem_init(&fft_mutex, 0, 0)){
       fprintf(stderr, "sem_init failed\n");
       return EXIT_FAILURE;        
    }
    
    if (!fftw_init_threads()) {
        printf("Error with threads\n");
        return;
    }
    fftw_plan_with_nthreads(6);
    pthread_t th1;
    pthread_create( & th1, NULL, fftCompute, NULL);
    printf("thread created\n");
    in = &fft_in;
    out = &fft_out;
    p = fftw_plan_dft_2d(TIMESIZE, FFTSIZE, in, out, FFTW_FORWARD, FFTW_MEASURE);
    printf("plan created\n");
   struct ftdi_context *ftdi;
   int err;
   exitRequested = 0;


   if ((ftdi = ftdi_new()) == 0)
   {
       fprintf(stderr, "ftdi_new failed\n");
       return EXIT_FAILURE;
   }
   
   if (ftdi_set_interface(ftdi, INTERFACE_A) < 0)
   {
       fprintf(stderr, "ftdi_set_interface failed\n");
       ftdi_free(ftdi);
       return EXIT_FAILURE;
   }
   
   if (ftdi_usb_open_desc(ftdi, 0xc0cc, 0xba11, NULL, NULL) < 0) 
   {
       fprintf(stderr, "Can't open ftdi device: %s\n",ftdi_get_error_string(ftdi));
       fprintf(stderr, "Ensure device C0CC:BA11 is connected\n");
       ftdi_free(ftdi);
       return EXIT_FAILURE;
   }
   else{
        printf("Device detected!\n");
   }
   
   /* A timeout value of 1 results in may skipped blocks */
   if(ftdi_set_latency_timer(ftdi, 2))
   {
       fprintf(stderr,"Can't set latency, Error %s\n",ftdi_get_error_string(ftdi));
       ftdi_usb_close(ftdi);
       ftdi_free(ftdi);
       return EXIT_FAILURE;
   }
   	
	signal(SIGINT, sigintHandler);
   
   err = ftdi_readstream(ftdi, readCallback, NULL, 8, 256);
   if (err < 0 && !exitRequested)
       exit(1);

   fprintf(stderr, "Program ended.\n");

   ftdi_usb_close(ftdi);
   ftdi_free(ftdi);
   signal(SIGINT, SIG_DFL);
   exit (0);
}

