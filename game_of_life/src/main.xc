// COMS20001 - Cellular Automaton Farm - Final Version
// Team 19 : Andrei Alexandru and Erich Reinholtz

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include "assert.h"

on tile[0] : in port buttons = XS1_PORT_4E;    //Port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;      //Port to access xCore-200 LEDs

on tile[0] : port p_scl = XS1_PORT_1E;         //Interface ports to orientation
on tile[0] : port p_sda = XS1_PORT_1F;


#define  IMHT 64                                //Image height
#define  IMWD 64                                //Image width
#define WN 8                                         //Number of workers(2/4/8)
#define MOD(a,b) ((((a)%(b))+(b))%(b))               //Mod function for negative numbers
#define generator 0                                  //Choose 0/1 tu turn off/on the image generator
typedef unsigned char uchar;                         //Using uchar as shorthand

char infname[] = "64x64.pgm";           //Input image path
char outfname[] = "testout.pgm";        //Output image path


#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

void test();

//------------------------------------------------------------------------------------
//TIMER
void ourTimer(chanend fromDist) {
    timer t;
    uint32_t startTime,         //Start time
             endTime,           //End time
             timeTaken = 0;     //Total time

    int paused = 0;             //Game state

    //Wait for signal from distributor to start
    fromDist :> int x;
    //Get start time from timer
    t :> startTime;

    while (1) {
        while (!paused){
            [[ordered]]
            select {
                // If distributor sends signal to pause
                case fromDist :> int x:
                    fromDist <: timeTaken;    //Send time to distributor
                    paused = 1;
                    break;
                // Check for overflow and add time
                default:
                    //Get end time from timer
                    t :> endTime;
                    // If overflow is hit, compensate
                    if (startTime > endTime) timeTaken = timeTaken + 42950;

                    //Add the elapsed time to timeTaken
                    timeTaken = timeTaken + endTime / 100000 - startTime / 100000;
                    startTime = endTime;
                    break;
            }
        }
        // Wait for signal from distributor to resume
        fromDist :> int x;
        paused = 0;
        //Get star time from timer
        t :> startTime;
    }
}


//------------------------------------------------------------------------------------
//DATA PACKER
uchar packData(int i, uchar pack, uchar pixelValue) {
    //If the pixel is dead
    if(pixelValue == 0)
      pack = pack & ~(1 << i);
    //If the pixel is alive
    else
      pack = pack | (1 << i);
    return pack;
}


//------------------------------------------------------------------------------------
//DATA UNPACKER
uchar unpackData(uchar pack, int i) {
    return (pack >> i) & 1;
}


//------------------------------------------------------------------------------------
//PACK PRINTER
void printBits(uchar source) {
    int temp;
    for(int i = 0; i<=7; i++) {
       temp = ((source >> i) & 1);
       printf("%d ", temp);
    }
}


//------------------------------------------------------------------------------------
//IMAGE READER
void DataInStream(char infname[], chanend c_out) {
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file or generate a random image
  if(!generator) {                                               //If the generator is turned off
    res = _openinpgm( infname, IMWD, IMHT );
    if( res ) {
      printf( "DataInStream: Error openening %s\n.", infname );
      return;
    }
  }

  //Read image line-by-line or generate random packss and send them to distributor
  for( int y = 0; y < IMHT; y++ ) {                   //Go through all lines
     if(!generator)                                           //If the generator is turned off
       _readinline( line, IMWD );
       uchar pack = 0;
     for( int x = 0; x < IMWD/8; x++ ) {              //Go through all packages
        for(int i=0; i<8; i++)                        //Go through every bit
           if(generator)
              pack = packData(i, pack, rand()%2);             //If the generator is turned on
           else
              pack = packData(i, pack, line[i + x*8]);        //If the generator is turned off
        c_out <: pack;      //Send the pack to the distributor
        //printBits(pack);                                 //Uncomment to print the image
        pack = 0;
     }
     //printf( "\n" );                                     //Uncomment to print the image
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}


//------------------------------------------------------------------------------------
//COUNTER FOR ALIVE NEIGHBOURS
int aliveCounter(int y, int x , int index,uchar image[IMHT/WN +2][IMWD/8]) {
    int alive = 0;                     //Number of alive neighbours
    uchar   Next,                      //The next cell
            Prev,                      //The previous cell
            Middle;                    //The middle cell

    for(int a = y-1; a <= y+1; a++) {                               //Go through the previous, current and next rows
       //Case:  the bit is at the beginning of the pack
       if(index == 0) {
         Next = unpackData(image[a][x] , index +1) ;
         Prev = unpackData(image[a][MOD(x-1,IMWD/8)] , 7);
       }
       else
         //Case: the bit is at the end of the pack
         if(index == 7) {
         Next = unpackData(image[a][MOD(x+1,IMWD/8)] , 0) ;
         Prev = unpackData(image[a][x] , index - 1);
         }
         //Case: the bit is in the middle of the pack
         else {
           Next = unpackData(image[a][x] , index + 1) ;
           Prev = unpackData(image[a][x] , index - 1);
         }
         Middle = unpackData(image[a][x], index);

         //Counting the alive neighbours
         if( Next == 1 )
           alive++;
         if( Prev == 1 )
           alive++;
         if(Middle == 1 )
           alive++;
    }
    return alive;
}


//------------------------------------------------------------------------------------
//WORKER IMPLEMENTATION
// n - the number of the worker
// pWorker - channel to the previous worker
// nWorker - channel to the next worker
void worker(chanend fromDistr,chanend pWorker,chanend nWorker, int n){
    int line = 0,                                                     //Initial matrix index
        totalAlive = 0,                                               //Initial total number of alive cells
        command;                                                      //The command from the distributor
    uchar image[IMHT/WN +2][IMWD/8],     //The matrix for storing the image
          packBackup,                       //The data pack's backup
          processedRow[IMWD/8];             //The matrix where it's stored the first prossed row

    //Store the packs from the distributor in a matrix
    for(int i = 1; i < IMHT/WN + 1; i++) {               //Go through all lines
       for(int j = 0; j< IMWD/8; j++) {                  //Go through all packages
          fromDistr :> image[i][j];
       }
    }

    //Worker starts
    while(1) {
        totalAlive = 0;
        //Transfer lines between workers :
        //If it's an even numbered worker
        if(n % 2 == 0) {
            //Receive data from the previous worker
            for(int i = 0; i< IMWD/8; i++)
                pWorker :> image[0][i];
            //Receive data from the next worker
            for(int i = 0; i< IMWD/8; i++)
                nWorker :> image[IMHT/WN +1][i];
            //Send data to the previous worker
            for(int i = 0; i< IMWD/8; i++)
                pWorker <: image[1][i];
            //Send data to the next worker
            for(int i = 0; i< IMWD/8; i++)
                nWorker <: image[IMHT/WN][i];
        }
        //If it's an odd numbered worker
        else {
            //Send data to the next worker
            for(int i = 0; i< IMWD/8; i++)
               nWorker <: image[IMHT/WN][i];
            //Send data to the previous worker
            for(int i = 0; i< IMWD/8; i++)
               pWorker <: image[1][i];
            //Receive data from the nex worker
            for(int i = 0; i< IMWD/8; i++)
               nWorker :> image[IMHT/WN +1][i];
            //Receive data from the previous worker
            for(int i = 0; i< IMWD/8; i++)
               pWorker :> image[0][i];
        }

        //Process the image
        for( int y = 1; y < IMHT/WN + 1; y++ ) {            //Go through all lines
            for( int x = 0; x < IMWD/8; x++ ) {              //Go through each pack in the line
              packBackup = image[y][x];               //Make a backup of the pack
              for( int index = 0; index < 8; index++) {     //Go through each bit in the pack
                 //Counting the alive neighbours
                 int alive = aliveCounter(y, x , index, image );

                 //Rules implementation:
                 //If the current cell is alive
                 if(unpackData(image[y][x], index) == 1) {
                   totalAlive ++;
                   alive--;                                                //Take out the current alive cell
                   if(alive < 2 || alive > 3)
                     packBackup = packData(index, packBackup, 0);          //The cell dies
                  }
                  //The current cell is dead
                  else
                   if(alive == 3)
                     packBackup = packData(index, packBackup, 1);          //The cell becomes alive
              }
              //If it's processing the second row
              if(y == 1)
                  processedRow[x] = packBackup;                         //Store the pack in the matrix
              //If it's processing the third row onwards
              if(y>1)
              image[0][x] = packBackup;                                //Store the pack in the first row, which is no longer needed
           }
           //If it's processing the third row onwards
           if( y > 1) {
             for( int x = 0; x < IMWD/8; x++ ) {        //Go through all packs
                image[y - 1][x] = processedRow[x];      //Update the previous row
                processedRow[x] = image[0][x];          //Update the processed row matrix
              }
            }
            //If it's processing the last row
            if( y == IMHT/WN)
              for( int x = 0; x < IMWD/8; x++ ){        //Go through all packs
                 image[y][x] = image[0][x];             //Update the current row
            }
        }
        //Wait from command from the distributor
        fromDistr :> command;
        if(command == 1)                                               //Send the packs to the distributor
          for(int i = 1; i < IMHT/WN +1 ; i++) {                //Go through all lines
             for(int j = 0; j< IMWD/8; j++) {                   //Go through all packages
               fromDistr <: image[i][j];
             }
          }

        if(command == 2)                                              //Send the number of the total alive cells to the distributor
          fromDistr <: totalAlive;
        line = 1 - line;                                //Update the matrix index
    }
}


//------------------------------------------------------------------------------------
//STATUS REPORT PRINTER
void statusReport(chanend fromAcc, uint32_t timeTaken, int rounds, int totalAlive ) {
    printf("Status report:\n"
               " Number of rounds processed: %d\n"
               " Current number of alive cells: %d\n"
               " Processing time : %dms\n", rounds, totalAlive, timeTaken);
    //Wait until the board is untilted
    fromAcc :> int x;
}


//------------------------------------------------------------------------------------
//DISTRIBUTOR
void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend time, out port leds, in port buttons, chanend worker[WN]) {
  int ledState = 0,                 //Initial led state
      buttonInput = 0,              //Initial button input
      tilted = 0,                   //Initial tilt state
      output = 0,                   //Initial output request
      i = 1,                        //Number of rounds processed
      totalAlive = 0,               //Total number of alive cells, per round
      alive = 0,
      command = 0;                  //Initial command
  uint32_t timeTaken;                                   //Time taken for processing
  uchar pack;                       //The pack received from DataInStream

  //Start testing
  test();

  //Starting up
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for SW1 to be pressed...\n" );
  //Wait for the SW 1 button to be pressed
  while(buttonInput != 14) {
  buttons :> buttonInput;
  }

  //Turn on the GREEN led
  leds <: 4;
  printf( "Processing...\n" );

  //Storing the image in the matrix
  for( int w = 0; w < WN; w++) {                //Go through each worker
      for(int i = 1; i < IMHT/WN + 1; i++) {    //Go through all lines
          for(int j = 0; j< IMWD/8; j++) {      //Go through each pack in the line
           c_in :> pack;                     //Read the pack
           worker[w] <: pack;                //Send the pakc to the worker
          }
      }
  }

  //Start timer
  time <: 1;
  //Game starts running
  while(1){
      totalAlive = 0;                               //For each round, totalAlive returns to 0
      command = 0;                                  //For each round, command returns to 0
      select {
          //Checks if the board is tilted
          case fromAcc :> int x:
              tilted = 1;
              printf("Tilted\n");
              break;
          default:
              //Checks if SW2 button is pressed
              buttons :> buttonInput;
                            if( buttonInput == 13) {
                            output = 1;
                            printf("Output request\n"); }

              break;
      }
      if(tilted)
          command = 2;
      else if (output)
          command = 1;
      //Send command to all workers
      for( int w = 0; w < WN; w++)   //Go through all workers
          worker[w] <: command;      //Send command to workers

      //Tell timer to pause
      time <: 1;
      time :> timeTaken;
    

      // If there was an output request:
      if(output){
        //Turn on the BLUE led
        leds <: 2;
        //Tell DataOutStream to open a new file
        c_out <: 1;
        printf( "DataOutStream: Start...\n" );
        //Send data to DataOutStream
        for( int w = 0; w < WN; w++) {                   //Go through all workers
            for(int i = 1; i < IMHT/WN + 1; i++) {       //Go through all lines
               for(int j = 0; j< IMWD/8; j++) {           //Go through each pack in the line
                  worker[w] :> pack;     //Receive pack from worker
                  c_out <: pack;         // Send pack to DataOutStream
               }
            }
        }
        output = 0;
      }

      //If the board is tilted
      if(tilted){
           for( int w = 0; w < WN; w++) {
               worker[w] :> alive;
               totalAlive = totalAlive + alive;}
           //Trun of the RED led
           leds <: 8;

           statusReport(fromAcc, timeTaken, i, totalAlive);
           tilted = 0;
      }
      //Resume timer
      time <: 1;

      i++;                                                    //Increment the number of rounds
      ledState = ledState ^ 1;                                //Change led state
      //Alternating the separate green led
      leds <: ledState;
  }
}



//------------------------------------------------------------------------------------
//IMAGE FILE WRITER
void DataOutStream(char outfname[], chanend c_in) {
  int res;
  uchar line[ IMWD ];

  while(1) {
      //Wait for signal from distributor
      c_in :> int x;
      //Open PGM file
      res = _openoutpgm( outfname, IMWD, IMHT );
      if( res ) {
        printf( "DataOutStream: Error opening %s\n.", outfname );
        return;
      }

      //Compile each line of the image and write the image line-by-line
      for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD/8; x++ ) {
            uchar pack;
            c_in :> pack;
            //Unpack the received data
            for(int i = 0 ; i <8; i++){
                int bit = unpackData(pack, i);
                if(bit == 0)
                    line[x*8 + i] = 0;
                else
                    line[x*8 + i] = 255;
            }
        }
        _writeoutline( line, IMWD );
      //  printf( "DataOutStream: Line written...\n" );
      }

      //Close the PGM image
      _closeoutpgm();
      printf( "DataOutStream: Done...\n" );
  }
  return;
}


//------------------------------------------------------------------------------------
//ORIENTATION READER AND INITIALISER
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }


  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1;
        toDist <: 1;
      }
    }
    else
      if(x < 10){
        tilted = 0;
        toDist <: 0;
      }
  }
}


//------------------------------------------------------------------------------------
// Tests
void testPackData()
{
    //Testing individual cases for packing
    assert(packData(5, 9, 255) == 41);
    assert(packData(5, 9, 0) == 9);

    //Simulating the packing of a segment of image line
    uchar line[8] = {255, 0, 0, 255, 0, 255};
    uchar pack = 0;

    for(int i=0; i<8; i++)
       pack = packData(i, pack, line[i]);

    assert(pack == 41);

    //Another similar packing of a line
    pack = 0;

    uchar line2[8] = {0, 0, 255, 0, 0, 255, 255, 0};

    for(int i=0; i<8; i++)
          pack = packData(i, pack, line2[i]);

    assert(pack == 100);
}

void testUnpackData()
{
    //Individual tests for unpackData
    assert(unpackData(41, 5) == 1);
    assert(unpackData(100, 6) == 1);
    assert(unpackData(100, 4) == 0);
}

void testAliveCounter()
{
    //Creating a test matrix
    uchar image[IMHT/WN+2][IMWD/8];

    //Filling the slots with an arbitrary value
    for(int i = 0; i<IMHT/WN+2; i++)
        for(int j = 0; j<IMWD/8; j++)
            image[i][j] = 69;

    //Individual tests

    assert(aliveCounter(2, 1, 0, image) == 3);
    assert(aliveCounter(2, 1, 1, image) == 6);
    assert(aliveCounter(2, 1, 2, image) == 3);
    assert(aliveCounter(2, 1, 3, image) == 3);
    assert(aliveCounter(2, 1, 4, image) == 0);
    assert(aliveCounter(2, 1, 5, image) == 3);

    assert(aliveCounter(2, 0, 0, image) == 3);
    assert(aliveCounter(2, 0, 1, image) == 6);
    assert(aliveCounter(2, 0, 2, image) == 3);
    assert(aliveCounter(2, 0, 3, image) == 3);
    assert(aliveCounter(2, 0, 4, image) == 0);
    assert(aliveCounter(2, 0, 5, image) == 3);

}

void test()
{
    testPackData();
    testUnpackData();
    testAliveCounter();
    printf("All tests pass\n");
}


//------------------------------------------------------------------------------------------------
//ORCHESTRATE CONCURRENT SYSTEM AND START UP ALL THREADS
int main(void) {
i2c_master_if i2c[1];               //Interface to orientation

chan c_inIO,                               //Channel to dataInStream
     c_outIO,                              //Channel to dataOutStream
     c_control,                            //Channel to orientation
     time,                                 //Channel for timer
     distToWorkers[WN],                    //Channels from distributors to workers
     workerToWorker[WN];                   //Channels from workers to workers

par {
    on tile[0] : i2c_master(i2c, 1, p_scl, p_sda, 10);                                                      //Server thread providing orientation data
    on tile[0] : orientation(i2c[0],c_control);                                                             //Client thread reading orientation data
    on tile[1] : DataInStream(infname, c_inIO);                                                             //Thread to read in a PGM image
    on tile[1] : DataOutStream(outfname, c_outIO);                                                          //Thread to write out a PGM image
    on tile[0] : distributor(c_inIO, c_outIO, c_control, time, leds, buttons, distToWorkers);               //Thread to coordinate work on image
    on tile[1] : ourTimer(time);                                                                            //Thread for timer

    par (int i = 0; i < WN/2 ; i++) {
       on tile[1] : worker(distToWorkers[i], workerToWorker[i], workerToWorker[(i+1) % WN], i);             //Threads for workers on tile[1]
    }

    par (int i = WN/2; i < WN ; i++) {
       on tile[0] : worker(distToWorkers[i], workerToWorker[i], workerToWorker[(i+1) % WN], i);             //Threads for workers on tile[0]
    }
}
return 0;
}
