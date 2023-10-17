//+--------------------------------------------------------------------------------------+
//                                                                    H I     L O W      |
//                                        Copyright ?RickD  BJF Trading Group 2006      |
//                                                             http://fxstrategy.ca      |
//                                                                                       |
//Experts http://fxstrategy.ca/experts.php      SALE! 50% OFF                            |
//Indicators http://fxstrategy.ca/products.php  SALE!50% OFF                             |
//Digital Filters Strategy http://fxstrategy.ca/digital_filtrs.php  SALE!50% OFF         |
//Trading Signals http://fxstrategy.ca/signals.php Two weeks FREE! No CC.                |
// forex calendar, research, article ....                                                |
//+--------------------------------------------------------------------------------------+
#property copyright "?RickD  BJF Trading Group 2006"                                    
#property link      "http://fxstrategy.ca/products.php"
//----
//----
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_color1  clrOrangeRed
#property indicator_color2  clrDodgerBlue
#property indicator_color3  clrMagenta
#property indicator_color4  clrChartreuse
//---
#include <dsrobotec.mqh>
//----
extern int BARS = 40;
extern double PORTION = 15.0;
//----
double UpperBuf[];
double LowerBuf[];
double SellEdge[];
double BuyEdge[];

double      vPoint;
int         vSlippage;
int         PipAdjust=0;
int         Slippage=10;

string   Font        = "Arial Bold";
color    FontColor   = clrYellow;
int      FontSize    = 14;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void init()
{       
    SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 1);
    SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, 1);
    SetIndexStyle(2, DRAW_LINE, STYLE_SOLID, 1);
    SetIndexStyle(3, DRAW_LINE, STYLE_SOLID, 1);
    //----   
    SetIndexDrawBegin(0, BARS);
    SetIndexDrawBegin(1, BARS);
    SetIndexDrawBegin(2, BARS);
    SetIndexDrawBegin(3, BARS);
    //----
    SetIndexBuffer(0, UpperBuf);
    SetIndexBuffer(1, LowerBuf);
    SetIndexBuffer(2, SellEdge);
    SetIndexBuffer(3, BuyEdge);
    
    if(Digits==5 || Digits==3) PipAdjust=10;
    else if(Digits==4 || Digits==2) PipAdjust=1;
    vPoint=Point*PipAdjust;
    vSlippage=Slippage*PipAdjust;

    string ps = GetPeriodString(Period());
   
    SetLabel("timeframe","timeframe = " + ps,10,120,FontColor,FontSize);
    SetLabel("bars","bars = " + IntegerToString(BARS),10,142,clrLimeGreen,FontSize);
    SetLabel("portion","portion = " + DoubleToString(PORTION,1),10,164,FontColor,FontSize);
   
    
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void deinit() 
  {
//----
  }  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void start() 
{
    double gap;
    
    int counted = IndicatorCounted();
    //----
    if(counted < 0) return;
    //----  
    if(counted > 0) counted--;
    
    int limit = Bars - counted;

    //----  
    for(int i = 0; i < limit; i++) 
    {
        UpperBuf[i] = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, BARS, i));        
        LowerBuf[i] = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, BARS, i));
        
        gap = UpperBuf[i] - LowerBuf[i];
        
        SellEdge[i] = UpperBuf[i]-gap*(PORTION/100);
        BuyEdge[i] = LowerBuf[i]+gap*(PORTION/100);
        
    }
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetLabel(string name,string text,int x,int y,color clr,int fontsize=8,string fontname="Arial")
  {
   if(ObjectFind(0,name)<0)
     {
      if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0))
        {
         printf("l=%d, error=%d, OBJ_LABEL %s :",__LINE__,GetLastError(),name);
         return;
        }
     }

   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontsize);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,FALSE);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetText(name,text,0,fontname,clr);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+