//+------------------------------------------------------------------+
//| Minero                                                           |
//+------------------------------------------------------------------+
#property   copyright   "DSRobotec, Inc."
#property   link        ""
#property   version     "2021.08"
#property   description "minero"
#property   strict

#define  MAX_EA            15
#define  MAX_CASCADE        5
#define  MAX_ESCALATION    13
#define  MAGIC_BASE        100000

#define  COLORBORDER    C'35,35,35'

#define  BUY         1
#define  SELL        2
#define  BUYLIMIT    3
#define  SELLLIMIT   4

double   MAXLOTS=0.11;
string   SS="^";
#include <dsrobotec.mqh>

enum EA_Mode
{
   Trade             = 0,
   NoTrade           = 1,
   NoNew_Finish      = 2,
   NoTradeBuyGrid    = 3,
   NoTradeSellGrid   = 4
};

enum Direction
{
   BOTH = 0,
   BUY_ONLY  = 1,
   SELL_ONLY  = 2
};

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input    int         EA_SEQ            = 0;
input    EA_Mode     EA_MODE           = Trade;
input    int         CASCADES          = 3;
input    Direction   TRADE_DIR         = BOTH;
input    int         MEASURE_MINUTES   = 60;       // Rapid up/down measure time (Minutes)

sinput   string      SEP01             = "=====================================================================";
input    int         ESCALATION        = 7;
input    int         GRID_LEG          = 310;
input    int         TP_OFFSET         = 440;
input    double      FIRSTLOTS         = 0.07; // MAX 0.05 for $10k
input    double      MULTIPLIER        = 1.72;
input    int         CASCADE_GAP       = 0;

sinput   string      SEP02             = "=====================================================================";
input    int         SLIPPAGE          = 20;
input    int         LIMITSPREAD       = 50;
sinput   bool        USETAKEPROFIT     = true;     // Use Order Takeprofit

sinput   string      SEP03             = "=====================================================================";
input    bool        SHOWMONITOR       = true;
input    bool        SHOWTPLINE        = true;     // Show Price Line (true:show, false:hide)
input    int         FONTSIZE          = 8;        // Monitor Font Size
input    color       COLORBUY          = clrDeepSkyBlue;
input    color       COLORSEL          = clrRed;
input    color       COLORCLOSEBUY     = clrDeepSkyBlue;
input    color       COLORCLOSESEL     = clrRed;

struct OrderStructure
{
   int               ticket;
   double            lots2entry;
   double            price2entry;
   datetime          opentime;
   double            lots;
   double            openprice;
   double            takeprofit;
   string            comment;
   int               magic;
   double            pl;
};

struct CascadeStructure
{
   int               maxidx;
   double            lots;
   double            pricelots;
   double            takeprofit;
   double            pl;
   double            price2close;
   OrderStructure    gOrder[];
};

CascadeStructure   cBuy[]; // Cascade Buy
CascadeStructure   cSel[]; // cascade Sell

struct CascadeParameter
{
   int               elapsed;
   double            tp_offset;  // points
   double            grid_gap;
   int               escalation;
   double            firstlot;
   double            lotmultiplier;
};

CascadeParameter C;


struct TickMaxMinInfo
{
   datetime          time;
   double            price;
};

struct TickInfo
{
   int               idx;
   datetime          time;
   TickMaxMinInfo    maxbid;
   TickMaxMinInfo    minbid;
   TickMaxMinInfo    maxask;
   TickMaxMinInfo    minask;
   TickMaxMinInfo    maxlast;
   TickMaxMinInfo    minlast;
};
TickInfo Tick[];
TickInfo TickMaxMin;

int      TickMaxMinIdx[][2];

int      Spread,IdxSymbol,IdxTick,MagicNumber=-1,OrderNumbers=0;
double   SpreadPoints,MaxDrawDown,MaxDrawDownPct;
bool     LockSpread,LockRapidBuy,LockRapidSel;
string   Message="";

string   Font = "Verdana";
int      FontSize,FontHeight;
datetime TimeNow,TimePrev;
string   DELIMETER=",";
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   int   i,xdist,ydist,total;
   string name;
   string gvname[];

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Alert("Check if automated trading is allowed in the terminal settings!");
      return(INIT_FAILED);
   }

//EA_SEQ=GetEA_SEQ();

   if(EA_SEQ<0)
   {
      printf("l=%d, No EA_SEQ is available",__LINE__);
      //ExpertRemove();
      return(INIT_FAILED);
   }

   if(CASCADES < 1 || CASCADES > MAX_CASCADE)
   {
      printf("l=%d, Wrong GridSet (1~%d)",__LINE__, MAX_CASCADE);
      return(INIT_FAILED);
   }

   if(EA_SEQ < 0 || EA_SEQ+1 > MAX_EA)   // MAX_EA=15
   {
      printf("Wrong EA Seq (1~%d)", MAX_EA);
      return(INIT_FAILED);
   }

   if(MEASURE_MINUTES < 1)
   {
      printf("l=%d, Wrong Rapid detect measure minutes",__LINE__);
      return(INIT_FAILED);
   }

   if(ESCALATION < 0 || ESCALATION > MAX_ESCALATION)   // MAX_ESCALATION=13
   {
      printf("l=%d, Wrong Escalation %d, (1~%d)", __LINE__, ESCALATION, MAX_ESCALATION);
      return(INIT_FAILED);
   }

   if(CASCADE_GAP < 0)
   {
      printf("l=%d, Wrong Grids(1~%d) or GridSet Gap", __LINE__, CASCADE_GAP);
      return(INIT_FAILED);
   }

   if(TP_OFFSET <= 0)
   {
      printf("Wrong Takeprofit");
      return(INIT_FAILED);
   }

   if(FIRSTLOTS < MarketInfo(_Symbol,MODE_MINLOT) || FIRSTLOTS > MAXLOTS)
   {
      printf("Wrong Lots (min:%.2f ~ max:%.2f)",MarketInfo(_Symbol,MODE_MINLOT),MAXLOTS);
      return(INIT_FAILED);
   }

   if(MULTIPLIER <= 0.0 || GRID_LEG <= 0.0)
   {
      printf("Wrong Lots Multiplier or Grid_Leg");
      return(INIT_FAILED);
   }

   if(LIMITSPREAD <= 0)
   {
      printf("Check Limit Spread");
      return(INIT_FAILED);
   }

   FontSize    = FONTSIZE;
   FontHeight  = FontSize*2;

   TimeNow = NULL;
   TimePrev = NULL;

   C.escalation         = ESCALATION;
   C.tp_offset          = NormalizeDouble(_Point * TP_OFFSET, _Digits);
   C.grid_gap           = NormalizeDouble(_Point * GRID_LEG, _Digits);
   C.elapsed            = MEASURE_MINUTES * 60;
   C.firstlot           = NormalizeDouble(MathMin(FIRSTLOTS,MAXLOTS),2);
   C.lotmultiplier      = MULTIPLIER;

   MaxDrawDown    = 0.0;
   MaxDrawDownPct = 0.0;

   ResizeGrid();

   total = OrdersTotal();

   ScanOrders(total);
   SetPriceLot2Order();

//+------------------------------------------------------------------+
//| Plot Monitor Start
//+------------------------------------------------------------------+
   if(SHOWMONITOR)
   {
      xdist = 0;
      ydist = FontHeight;

      PlotTableTradeSet(xdist,ydist);

      xdist = 0;
      ydist += (int)(FontHeight*1.5);

      PlotTableGridSet(xdist,ydist);

      PlotDataTradeSet();
      PlotDataGridSet();
   }

   if(SHOWTPLINE) CreateTPLine();

//+------------------------------------------------------------------+
//| TickInfo Initialization Start
//+------------------------------------------------------------------+
   if(ArrayResize(Tick,MEASURE_MINUTES) != MEASURE_MINUTES)
      PrintError(__LINE__);

   if(ArrayResize(TickMaxMinIdx,MEASURE_MINUTES) != MEASURE_MINUTES*2)
      PrintError(__LINE__);

   for(i=0; i<MEASURE_MINUTES; i++)
   {
      Tick[i].idx    = i;
      Tick[i].time   = i;

      InitTickMaxMin(Tick[i]);

      TickMaxMinIdx[i][0]  = i;
      TickMaxMinIdx[i][1]  = i;
   }

   IdxTick = 0;
//+------------------------------------------------------------------+
//| TickInfo Initialization End
//+------------------------------------------------------------------+

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int GetEA_SEQ()
{
   int c,i,j,k,total,sfind,lastseq=0,easeq[],seq=0,available_seq=-1,ea_seq=-1;
   string gvprefix="EA_SEQ-";
//---
   string name, gvname[];
//datetime gvtime;
   bool  gvtemp=FALSE;

   string sep="_";
   ushort u_sep;
   string result[];
   u_sep=StringGetCharacter(sep,0);

   total = GlobalVariablesTotal();
   ArrayResize(gvname,total);

   j=0;
   total=GlobalVariablesTotal();
   ArrayResize(easeq,total);
   for(i=0; i<total; i++)
   {
      name = GlobalVariableName(i);
      sfind=StringFind(name,gvprefix,0);
      if(sfind==0)   // if global variable contains "EA_SEQ" from oth character
      {
         //printf("i=%d, name=%s",i,name);
         k=StringSplit(name,u_sep,result);
         //printf("l=%d, k=%d",__LINE__,k);
         if(k==2)
         {
            gvname[j]=name;
            easeq[j]=(int)StringToInteger(result[1]);
            j++;
         }
      }
   }

   printf("l=%d, There are %d running EAs",__LINE__,j+1);

   if(j>=1)
   {
      ArrayResize(easeq,j);
      ArraySort(easeq,WHOLE_ARRAY,0,MODE_ASCEND);
      //printf("j=%d,last=%d",j,easeq[j-1]);
   }
   else     // EA_SEQ-0 is available only
   {
      name=gvprefix + "0";
      if(!GlobalVariableCheck(name))
      {
         GlobalVariableTemp(name);
         printf("l=%d, GlobalVariableTemp=%s",__LINE__,name);
         return(0);
      }
   }

   if(j>=MAX_EA)
   {
      printf("l=%d, Total EA seq:%d over MAX_EA:%d",__LINE__,j,MAX_EA);
      ea_seq=-1;
      return(ea_seq);
   }

   for(i=0; i<j; i++)
   {
      for(c=0; c<MAX_EA; c++)
      {
         if(easeq[i]==c)
            continue;
         else
         {
            name = gvprefix + IntegerToString(c);
            if(!GlobalVariableCheck(name))
            {
               GlobalVariableTemp(name);
               printf("l=%d, GVTemp=%s",__LINE__,name);
               ea_seq = c;
               return(ea_seq);
            }
         }
      }
   }

   return(ea_seq);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   int      i,total;
   bool     order;
   MqlTick  lasttick;

   if(!SymbolInfoTick(_Symbol,lasttick))
      PrintError(__LINE__);

   TimeNow = TimeCurrent();

   if(TimePrev == NULL || TimeMinute(TimeNow) != TimeMinute(TimePrev))
   {
      if(ArraySort(TickMaxMinIdx,WHOLE_ARRAY,0,MODE_ASCEND))
      {
         IdxTick = TickMaxMinIdx[0][1];
         Tick[IdxTick].time = lasttick.time;
         InitTickMaxMin(Tick[IdxTick]);
         CheckTickMaxMin(Tick[IdxTick],
                         lasttick.time,lasttick.bid,lasttick.time,lasttick.bid,
                         lasttick.time,lasttick.ask,lasttick.time,lasttick.ask,
                         lasttick.time,lasttick.last,lasttick.time,lasttick.last);
         InitTickMaxMin(TickMaxMin);
         for(i=0; i<MEASURE_MINUTES; i++)
         {
            TickMaxMinIdx[i][0] = (int)Tick[i].time;
            TickMaxMinIdx[i][1] = i;
            CheckTickMaxMin(TickMaxMin,
                            Tick[i].maxbid.time,Tick[i].maxbid.price,Tick[i].minbid.time,Tick[i].minbid.price,
                            Tick[i].maxask.time,Tick[i].maxask.price,Tick[i].minask.time,Tick[i].minask.price,
                            Tick[i].maxlast.time,Tick[i].maxlast.price,Tick[i].minlast.time,Tick[i].minlast.price);
         }
      }
      else
         PrintError(__LINE__);
   }
   else
   {
      CheckTickMaxMin(Tick[IdxTick],
                      lasttick.time,lasttick.bid,lasttick.time,lasttick.bid,
                      lasttick.time,lasttick.ask,lasttick.time,lasttick.ask,
                      lasttick.time,lasttick.last,lasttick.time,lasttick.last);

      CheckTickMaxMin(TickMaxMin,
                      Tick[IdxTick].maxbid.time,Tick[IdxTick].maxbid.price,Tick[IdxTick].minbid.time,Tick[IdxTick].minbid.price,
                      Tick[IdxTick].maxask.time,Tick[IdxTick].maxask.price,Tick[IdxTick].minask.time,Tick[IdxTick].minask.price,
                      Tick[IdxTick].maxlast.time,Tick[IdxTick].maxlast.price,Tick[IdxTick].minlast.time,Tick[IdxTick].minlast.price);
   }

   Spread = (int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   SpreadPoints = Spread * _Point;

   if(Spread >= LIMITSPREAD) LockSpread = true;
   else LockSpread = false;

   if(Bid - TickMaxMin.minbid.price > C.grid_gap) 
   {
      LockRapidSel = true;
      //printf("l=%d, Bid - TickMaxMin.minbid.price = %s, C.grid_gap = %s",__LINE__, pds(Bid - TickMaxMin.minbid.price), pds(C.grid_gap));
   }   
   else LockRapidSel = false;

   if(TickMaxMin.maxask.price - Ask > C.grid_gap) 
   {
      LockRapidBuy = true;
      //printf("l=%d, Bid - TickMaxMin.maxask.price = %s, C.grid_gap = %s",__LINE__, pds(TickMaxMin.maxask.price - Ask), pds(C.grid_gap));
   }      
   else LockRapidBuy = false;

   order = chkSignal();
   total = OrdersTotal();

   if(order || total != OrderNumbers)
   {
      ScanOrders(total);
      SetPriceLot2Order();
      OrderNumbers = total;

      if(SHOWMONITOR)
      {
         PlotDataGridSet();
      }

      if(SHOWTPLINE)
      {
         DeleteTPLine();
         CreateTPLine();
      }

   }

   if(SHOWMONITOR) PlotDataTradeSet();

   TimePrev = TimeNow;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void InitCascade()
{
   int   cidx, oidx;

   for(cidx=0; cidx<CASCADES; cidx++)
   {
      cBuy[cidx].maxidx       = -1;
      cBuy[cidx].lots         = 0.0;
      cBuy[cidx].pricelots    = 0.0;
      cBuy[cidx].takeprofit   = 0.0;
      cBuy[cidx].pl           = 0.0;
      cBuy[cidx].price2close  = MAXVALUE;

      cSel[cidx].maxidx       = -1;
      cSel[cidx].lots         = 0.0;
      cSel[cidx].pricelots    = 0.0;
      cSel[cidx].takeprofit   = 0.0;
      cSel[cidx].pl            = 0.0;
      cSel[cidx].price2close  = MINVALUE;

      for(oidx=0; oidx<=C.escalation ; oidx++)
      {
         cBuy[cidx].gOrder[oidx].ticket        = -1;
         cBuy[cidx].gOrder[oidx].opentime      = NULL;
         cBuy[cidx].gOrder[oidx].lots2entry    = 0.0;
         cBuy[cidx].gOrder[oidx].price2entry   = MINVALUE;
         cBuy[cidx].gOrder[oidx].lots          = 0.0;
         cBuy[cidx].gOrder[oidx].openprice     = 0.0;
         cBuy[cidx].gOrder[oidx].takeprofit    = 0.0;
         cBuy[cidx].gOrder[oidx].comment       = "";
         cBuy[cidx].gOrder[oidx].magic         = -1;
         cBuy[cidx].gOrder[oidx].pl            = 0.0;

         cSel[cidx].gOrder[oidx].ticket        = -1;
         cSel[cidx].gOrder[oidx].opentime      = NULL;
         cSel[cidx].gOrder[oidx].lots2entry    = 0.0;
         cSel[cidx].gOrder[oidx].price2entry   = MAXVALUE;
         cSel[cidx].gOrder[oidx].lots          = 0.0;
         cSel[cidx].gOrder[oidx].openprice     = 0.0;
         cSel[cidx].gOrder[oidx].takeprofit    = 0.0;
         cSel[cidx].gOrder[oidx].comment       = "";
         cSel[cidx].gOrder[oidx].magic         = -1;
         cSel[cidx].gOrder[oidx].pl            = 0.0;
      }
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void InitTickMaxMin(TickInfo &tickinfo)
{
   tickinfo.maxbid.time    = NULL;
   tickinfo.maxbid.price   = MINVALUE;
   tickinfo.minbid.time    = NULL;
   tickinfo.minbid.price   = MAXVALUE;

   tickinfo.maxask.time    = NULL;
   tickinfo.maxask.price   = MINVALUE;
   tickinfo.minask.time    = NULL;
   tickinfo.minask.price   = MAXVALUE;

   tickinfo.maxlast.time    = NULL;
   tickinfo.maxlast.price   = MINVALUE;
   tickinfo.minlast.time    = NULL;
   tickinfo.minlast.price   = MAXVALUE;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckTickMaxMin(TickInfo &tickinfo,
                     const datetime timemaxbid, const double maxbid, const datetime timeminbid, const double minbid,
                     const datetime timemaxask, const double maxask, const datetime timeminask, const double minask,
                     const datetime timemaxlast,  const double maxlast, const datetime timeminlast, const double minlast)
{
   if(tickinfo.maxbid.price < maxbid)
   {
      tickinfo.maxbid.time    = timemaxbid;
      tickinfo.maxbid.price   = maxbid;
   }

   if(tickinfo.minbid.price > minbid)
   {
      tickinfo.minbid.time    = timeminbid;
      tickinfo.minbid.price   = minbid;
   }

   if(tickinfo.maxask.price < maxask)
   {
      tickinfo.maxask.time    = timemaxask;
      tickinfo.maxask.price   = maxask;
   }

   if(tickinfo.minask.price > minask)
   {
      tickinfo.minask.time    = timeminask;
      tickinfo.minask.price   = minask;
   }

   if(tickinfo.maxlast.price < maxlast)
   {
      tickinfo.maxlast.time    = timemaxlast;
      tickinfo.maxlast.price   = maxlast;
   }

   if(tickinfo.minlast.price > minlast)
   {
      tickinfo.minlast.time    = timeminlast;
      tickinfo.minlast.price   = minlast;
   }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool commentParsing(string comment, int &otype, int &easeq, int &cidx, int &oidx)
{
   // for comment parsing
   int k;
   string sep=SS;
   ushort u_sep;
   string result[];
   u_sep=StringGetCharacter(sep,0);
   int   buysel=0,easequence=1,cascadeno=2,orderno=3,symbolname=4,chartid=5,argcnt=6;
   //---
   k=StringSplit(comment,u_sep,result);
   if(k != argcnt)
   {
      printf("l=%d, It is not my EA controlled order. comment=%s",__LINE__, comment);
      return(false); // comment format is not like "B^0^0^0^SYMBOL^chartid"
   }

   if(result[buysel]=="B")       otype = OP_BUY;
   else if(result[buysel]=="S")  otype = OP_SELL;
   else 
   {
      otype = -999; 
      printf("l=%d, Order is not BUY or SELL",__LINE__); 
      return(false);
   }

   easeq    = (int)StringToInteger(result[easequence]);
   if(easeq!=EA_SEQ) return(false);
   
   cidx    = (int)StringToInteger(result[cascadeno]);
   if(cidx<0 || cidx>(CASCADES-1)) return(false); 
   
   oidx    = (int)StringToInteger(result[orderno]);
   if(oidx<0 || oidx>(C.escalation-1)) return(false);
   
   printf("l=%d, comment=%s, otype=%s,easeq=%d,cidx=%d,oidx=%d",__LINE__,comment,result[buysel],easeq,cidx,oidx);
   return(true);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ScanOrders(int total)
{
   int      c, ticket, ordertype, magic, easeq, otype, cidx, oidx, err;
   string   comment;
   double   lots, openprice, commission, takeprofit, swap, profit;
   datetime opentime;

   InitCascade();

   for(c=0; c<total; c++)
   {
      if(OrderSelect(c,SELECT_BY_POS))
      {
         ticket=OrderTicket();opentime=OrderOpenTime();ordertype=OrderType();lots=OrderLots();
         openprice=OrderOpenPrice();takeprofit=OrderTakeProfit();commission=OrderCommission();
         swap=OrderSwap();profit=OrderProfit();magic=OrderMagicNumber();comment=OrderComment();

         /*
         k=StringSplit(comment,u_sep,result);
         if(k != argcnt)
         {
            printf("l=%d, It is not my EA controlled order. ticket=%d, magic=%d, comment=%s",__LINE__, ticket, magic, comment);
            continue; // comment format is not like "B^0^0^0^SYMBOL^chartid"
         }

         if(result[buysel]=="B")       otype = OP_BUY;
         else if(result[buysel]=="S")  otype = OP_SELL;
         else printf("l=%d, Order is not BUY or SELL",__LINE__);

         easeq    = (int)StringToInteger(result[easequence]);
         cidx    = (int)StringToInteger(result[cascadeno]);
         oidx    = (int)StringToInteger(result[orderno]);
         */
         if(OrderSymbol() != _Symbol) continue;
         else if(magic != MAGIC_BASE+EA_SEQ) continue;
         else if(!commentParsing(comment,otype,easeq,cidx,oidx)) continue;
         
         /*else if((otype < OP_BUY || otype > OP_SELL) || (cidx < 0 || cidx > CASCADES-1) || oidx < 0)
         {
            printf("l=%d, magic=%d, easeq=%d, cidx=%d, otype=%d, oidx=%d",__LINE__, magic, easeq, cidx, otype, oidx);
            continue;
         }
         */
         
         switch(otype)
         {
            case OP_BUY:
               if(cBuy[cidx].gOrder[oidx].ticket >= 0) printf("l=%d, Error : Duplication of Buy cidx=%d, oidx=%d", __LINE__,cidx,oidx);
               break;
            case OP_SELL:
               if(cSel[cidx].gOrder[oidx].ticket >= 0) printf("l=%d, Error : Duplication of Sell cidx=%d, oidx=%d, l=%d", __LINE__,cidx,oidx);
               break;
            default:
               break;
         }

         if(otype == OP_BUY && ordertype == OP_BUY)
         {
            cBuy[cidx].gOrder[oidx].ticket     = ticket;
            cBuy[cidx].gOrder[oidx].opentime   = opentime;
            cBuy[cidx].gOrder[oidx].lots       = lots;
            cBuy[cidx].gOrder[oidx].openprice  = openprice;
            cBuy[cidx].gOrder[oidx].takeprofit = takeprofit;
            cBuy[cidx].gOrder[oidx].comment    = comment;
            cBuy[cidx].gOrder[oidx].magic      = magic;
            cBuy[cidx].gOrder[oidx].pl         = profit + swap + commission;

            cBuy[cidx].maxidx       = MathMax(oidx,cBuy[cidx].maxidx);
            cBuy[cidx].takeprofit   = takeprofit;

            cBuy[cidx].lots         += lots;
            cBuy[cidx].pricelots    += openprice * lots;
            cBuy[cidx].pl           += profit+commission+swap;
         }
         else if(otype == OP_SELL && ordertype == OP_SELL)
         {
            cSel[cidx].gOrder[oidx].ticket     = ticket;
            cSel[cidx].gOrder[oidx].opentime   = opentime;
            cSel[cidx].gOrder[oidx].lots       = lots;
            cSel[cidx].gOrder[oidx].openprice  = openprice;
            cSel[cidx].gOrder[oidx].takeprofit = takeprofit;
            cSel[cidx].gOrder[oidx].comment    = comment;
            cSel[cidx].gOrder[oidx].magic      = magic;
            cSel[cidx].gOrder[oidx].pl         = profit+commission+swap;

            cSel[cidx].maxidx       = MathMax(oidx,cSel[cidx].maxidx);
            cSel[cidx].takeprofit   = takeprofit;

            cSel[cidx].lots         += lots;
            cSel[cidx].pricelots    += openprice * lots;
            cSel[cidx].pl           += profit+commission+swap;
         }
      }
      else
      {
         err=GetLastError();
         printf("l=%d, OrderSelect errno=%d, %s",__LINE__,err,ErrorDescription(err));
      }   
   } // for
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetPriceLot2Order()
{
   int      i,j,err;
   double   price2entry;
//datetime timecurr=TimeCurrent();

   for(i=0; i<CASCADES; i++)
   {
      //+------------------------------------------------------------------+
      //| Set cBuy for Empty Cascade                                       |
      //+------------------------------------------------------------------+
      if(cBuy[i].maxidx < 0) // i th Cascade is empty 
      {
         cBuy[i].gOrder[0].lots2entry = C.firstlot;
         if(i == 0) 
         {
            cBuy[i].gOrder[0].price2entry = Ask;
         }   
         else
         {
            price2entry = NormalizeDouble(cBuy[i-1].gOrder[C.escalation].price2entry - C.grid_gap*CASCADE_GAP,_Digits);
            if(Ask < price2entry) price2entry = Ask;
            cBuy[i].gOrder[0].price2entry = price2entry+SpreadPoints;
         }

         for(j=1; j<=C.escalation ; j++)
         {
            cBuy[i].gOrder[j].lots2entry = NormalizeDouble(cBuy[i].gOrder[0].lots2entry*MathPow(C.lotmultiplier,j),2);
            cBuy[i].gOrder[j].price2entry   = NormalizeDouble(cBuy[i].gOrder[j-1].price2entry - C.grid_gap,_Digits);
            //+------------------------------------------------------------------+
            //| grid gap algorithm - by price low, med, high                     |
            //+------------------------------------------------------------------+
         }
      }
      //+------------------------------------------------------------------+
      //| Cascade has some order                                           |
      //+------------------------------------------------------------------+      
      else
      {
         if(cBuy[i].gOrder[0].openprice != 0.0)
         {
            cBuy[i].gOrder[0].lots2entry    = cBuy[i].gOrder[0].lots;
            cBuy[i].gOrder[0].price2entry   = cBuy[i].gOrder[0].openprice;
         }
         else
         {
            for(j=1; j<=cBuy[i].maxidx; j++)
            {
               if(cBuy[i].gOrder[j].openprice != 0.0)
               {
                  cBuy[i].gOrder[0].lots2entry    = C.firstlot;
                  cBuy[i].gOrder[0].price2entry   = NormalizeDouble(cBuy[i].gOrder[j].price2entry + C.grid_gap*j,_Digits);
                  break;
               }
            }
         }

         for(j=1; j<=C.escalation ; j++)
         {
            if(cBuy[i].gOrder[j].openprice == 0.0)
            {
               cBuy[i].gOrder[j].lots2entry    = NormalizeDouble(cBuy[i].gOrder[0].lots2entry*MathPow(C.lotmultiplier,j),2);
               cBuy[i].gOrder[j].price2entry   = NormalizeDouble(cBuy[i].gOrder[j-1].price2entry - C.grid_gap,_Digits);
               //+------------------------------------------------------------------+
               //| grid gap algorithm - by price low, med, high                     |
               //+------------------------------------------------------------------+
            }
            else
            {
               cBuy[i].gOrder[j].lots2entry    = cBuy[i].gOrder[j].lots;
               cBuy[i].gOrder[j].price2entry   = cBuy[i].gOrder[j].openprice;
            }
         }

         cBuy[i].price2close = cBuy[i].gOrder[cBuy[i].maxidx].openprice + C.tp_offset;

         if(USETAKEPROFIT)
         {
            for(j=cBuy[i].maxidx; j>=0; j--)
            {
               if(cBuy[i].gOrder[j].ticket >= 0)
               {
                  RefreshRates();
                  if(OrderSelect(cBuy[i].gOrder[j].ticket,SELECT_BY_TICKET))
                  {
                     double tp=NormalizeDouble(OrderTakeProfit(),_Digits);
                     double p2c=NormalizeDouble(cBuy[i].price2close,_Digits);
                     //if(OrderTakeProfit() != cBuy[i].price2close)
                     if(tp != p2c)
                     {
                        if(!OrderModify(OrderTicket(), OrderOpenPrice(), 0.0, p2c,0))
                        {
                           err=GetLastError();
                           if(err != ERR_NO_ERROR) printf("l=%d, OrderModify ticket=%d, err=%s",__LINE__,OrderTicket(),errMsg(err));
                        }
                     }
                  }
                  else
                  {
                     err=GetLastError();
                     if(err != ERR_NO_ERROR) printf("l=%d, OrderSelect ticket=%d, err=%s",__LINE__,OrderTicket(),errMsg(err));
                  }
               }
            }
         }
         else
         {
            for(j=cBuy[i].maxidx; j>=0; j--)
            {
               if(cBuy[i].gOrder[j].ticket >= 0)
               {
                  if(OrderSelect(cBuy[i].gOrder[j].ticket,SELECT_BY_TICKET))
                  {
                     if(OrderTakeProfit() != 0.0)
                     {
                        RefreshRates();
                        if(!OrderModify(OrderTicket(), OrderOpenPrice(), 0.0, 0.0,0))
                        {
                           err=GetLastError();
                           if(err != ERR_NO_ERROR) printf("l=%d, OrderModify err=%s",__LINE__,errMsg(err));
                        }
                     }
                  }
                  else // OrderSelect
                  {
                     err=GetLastError();
                     if(err != ERR_NO_ERROR) printf("l=%d, OrderSelect errorno=%d, err=%s",__LINE__,err,errMsg(err));
                  }
               }
            }
         }
      }
   } // for
   //+------------------------------------------------------------------+
   // Set cBuy End
   //+------------------------------------------------------------------+

   for(i=0; i<CASCADES; i++)
   {
      //+------------------------------------------------------------------+
      //| Set cSel, if Empty Cascade                                       |
      //+------------------------------------------------------------------+
      if(cSel[i].maxidx < 0)
      {
         cSel[i].gOrder[0].lots2entry = C.firstlot;
         if(i == 0)
         {
            cSel[i].gOrder[0].price2entry   = Bid;
         }
         else
         {
            price2entry = NormalizeDouble(cSel[i-1].gOrder[C.escalation ].price2entry + C.grid_gap*CASCADE_GAP,_Digits);
            if(Bid > price2entry) price2entry = Bid;
            cSel[i].gOrder[0].price2entry   = price2entry-SpreadPoints;
         }

         for(j=1; j<=C.escalation ; j++)
         {
            //cSel[i].gOrder[j].lots2entry    = NormalizeDouble(MathMin(MathMax(cSel[i].gOrder[0].lots2entry*MathPow(C.lotmultiplier,j),MarketInfo(_Symbol,MODE_MINLOT)),MarketInfo(_Symbol,MODE_MAXLOT)),2);
            cSel[i].gOrder[j].lots2entry    = NormalizeDouble(cSel[i].gOrder[0].lots2entry*MathPow(C.lotmultiplier,j),2);
            cSel[i].gOrder[j].price2entry   = NormalizeDouble(cSel[i].gOrder[j-1].price2entry + C.grid_gap,_Digits);
            //+------------------------------------------------------------------+
            //| grid gap algorithm - by price low, med, high                     |
            //+------------------------------------------------------------------+

         }
      }
      //+------------------------------------------------------------------+
      //| Cascade has some order                                           |
      //+------------------------------------------------------------------+
      else
      {
         if(cSel[i].gOrder[0].openprice != 0.0)
         {
            cSel[i].gOrder[0].lots2entry    = cSel[i].gOrder[0].lots;
            cSel[i].gOrder[0].price2entry   = cSel[i].gOrder[0].openprice;
         }
         else
         {
            for(j=1; j<=cSel[i].maxidx; j++)
            {
               if(cSel[i].gOrder[j].openprice != 0.0)
               {
                  cSel[i].gOrder[0].lots2entry    = C.firstlot;
                  cSel[i].gOrder[0].price2entry   = NormalizeDouble(cSel[i].gOrder[j].price2entry - C.grid_gap*j,_Digits);
                  break;
               }
            }
         }

         for(j=1; j<=C.escalation ; j++)
         {
            if(cSel[i].gOrder[j].openprice == 0.0)
            {
               //cSel[i].gOrder[j].lots2entry    = NormalizeDouble(MathMin(MathMax(cSel[i].gOrder[0].lots2entry*MathPow(C.lotmultiplier,j),MarketInfo(_Symbol,MODE_MINLOT)),MarketInfo(_Symbol,MODE_MAXLOT)),2);
               cSel[i].gOrder[j].lots2entry    = NormalizeDouble(MathMin(MathMax(cSel[i].gOrder[0].lots2entry*MathPow(C.lotmultiplier,j),MarketInfo(_Symbol,MODE_MINLOT)),MarketInfo(_Symbol,MODE_MAXLOT)),2);
               cSel[i].gOrder[j].price2entry   = NormalizeDouble(cSel[i].gOrder[j-1].price2entry + C.grid_gap,_Digits);
               //+------------------------------------------------------------------+
               //| grid gap algorithm - by price low, med, high                     |
               //+------------------------------------------------------------------+

            }
            else
            {
               cSel[i].gOrder[j].lots2entry    = cSel[i].gOrder[j].lots;
               cSel[i].gOrder[j].price2entry   = cSel[i].gOrder[j].openprice;
            }
         }

         cSel[i].price2close = cSel[i].gOrder[cSel[i].maxidx].openprice - C.tp_offset;

         if(USETAKEPROFIT)
         {
            for(j=cSel[i].maxidx; j>=0; j--)
            {
               if(cSel[i].gOrder[j].ticket >= 0)
               {
                  RefreshRates();
                  if(OrderSelect(cSel[i].gOrder[j].ticket,SELECT_BY_TICKET))
                  {
                     double tp=NormalizeDouble(OrderTakeProfit(),_Digits);
                     double p2c=NormalizeDouble(cSel[i].price2close,_Digits);
                     if(tp != p2c)
                     {
                        if(!OrderModify(OrderTicket(), OrderOpenPrice(), 0.0, p2c,0))
                        {
                           err=GetLastError();
                           if(err != ERR_NO_ERROR) printf("l=%d, OrderModify err=%s",__LINE__,errMsg(err));
                        }
                     }
                  }
                  else // OrderSelect
                  {
                     err=GetLastError();
                     if(err != ERR_NO_ERROR) printf("l=%d, OrderSelect err=%s",__LINE__,errMsg(err));
                  }
               }
            }
         }
         else // !USETAKEPROFIT
         {
            for(j=cSel[i].maxidx; j>=0; j--)
            {
               if(cSel[i].gOrder[j].ticket >= 0)
               {
                  if(OrderSelect(cSel[i].gOrder[j].ticket,SELECT_BY_TICKET))
                  {
                     if(OrderTakeProfit() != 0.0)
                     {
                        RefreshRates();
                        if(!OrderModify(OrderTicket(), OrderOpenPrice(), 0.0, 0.0, 0))
                        {
                           err=GetLastError();
                           if(err != ERR_NO_ERROR) printf("l=%d, OrderModify err=%s",__LINE__,errMsg(err));
                        }
                     }
                  }
                  else // OrderSelect
                  {
                     err=GetLastError();
                     if(err != ERR_NO_ERROR) printf("l=%d, OrderModify err=%s",__LINE__,errMsg(err));
                  }
               }
            }
         }
      }
      //+------------------------------------------------------------------+
      // Set cSel End
      //+------------------------------------------------------------------+
   } // for
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool chkSignal()
{
   int      i,j,ticket,magic,idx=-1,err,cid;
   double   lots=0.0,openprice=0.0,tp=0.0,profit=0.0,swap=0.0,commission=0.0;
   string   comment;
   bool     signalon=false,ret=false;
//datetime timecurr=TimeCurrent();

   if(!USETAKEPROFIT)
   {
      /*Bcascade=0;
      for(i=0; i<CASCADES; i++)
      {
         if(cBuy[i].maxidx >=0) Bcascade++;
      }
      for(i=0; i<Bcascade; i++) ...
      */   
      for(i=0; i<CASCADES; i++)
      {
         if(cBuy[i].maxidx >= 0 && Bid >= cBuy[i].price2close) CloseOrderBuy(i);
         if(cSel[i].maxidx >= 0 && Ask <= cSel[i].price2close) CloseOrderSel(i);
      }
   }

   if(EA_MODE == NoTrade || LockSpread) return(false);

//+------------------------------------------------------------------+
//| BUY                                                              |
//+------------------------------------------------------------------+
   if(TRADE_DIR != SELL_ONLY && !LockRapidBuy)
   {
      for(i=0; i<CASCADES; i++)
      {
         signalon = false;
         if(cBuy[i].maxidx < 0)
         {
            if(EA_MODE != NoNew_Finish && EA_MODE != NoTradeBuyGrid)
            {
               if(Ask <= cBuy[i].gOrder[0].price2entry)
               {
                  signalon = true;
                  lots     = cBuy[i].gOrder[0].lots2entry;
                  idx      = 0;
               }
            }
         }
         else if(cBuy[i].maxidx < C.escalation -1)
         {
            for(j=cBuy[i].maxidx+1; j<C.escalation ; j++)
            {
               if(cBuy[i].gOrder[j].openprice != 0.0)
                  continue;
               else if(Ask > cBuy[i].gOrder[j].price2entry)
                  break;
               else if(Ask <= cBuy[i].gOrder[j].price2entry && Ask >= cBuy[i].gOrder[j].price2entry-SpreadPoints)
               {
                  signalon = true;
                  lots     = cBuy[i].gOrder[j].lots2entry;
                  idx      = j;
                  break;
               }
            }
         }

         if(signalon)
         {
            magic    = MAGIC_BASE + EA_SEQ;
            cid = (int)ChartID();
            //string symbol=StringSubstr(_Symbol,0,1) + StringSubstr(_Symbol,3,1);
            //comment  = "B^" + IntegerToString(EA_SEQ) + SS + IntegerToString(i) + SS + IntegerToString(idx) + SS
            //           + _Symbol + SS + IntegerToString((int)MathMod((int)cid,1000));
            comment = getComment("B",EA_SEQ,i,idx);
            ticket = OrderSend(_Symbol,OP_BUY,lots,Ask,SLIPPAGE,0.0,0.0,comment,magic,0,COLORBUY);
            if(ticket>0)
            {
               ret = true;
               if(USETAKEPROFIT)
               {
                  if(idx > cBuy[i].maxidx)
                  {
                     if(OrderSelect(ticket,SELECT_BY_TICKET))
                     {
                        openprice   = OrderOpenPrice();
                        tp          = NormalizeDouble(openprice + C.tp_offset,_Digits);
                        RefreshRates();
                        if(!OrderModify(OrderTicket(), openprice, 0.0, tp,0))
                        {
                           err=GetLastError();
                           if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                        }
                     }
                     else
                     {
                        err=GetLastError();
                        if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                     }

                     for(j=cBuy[i].maxidx; j>=0; j--)
                     {
                        if(OrderSelect(cBuy[i].gOrder[j].ticket,SELECT_BY_TICKET))
                        {
                           RefreshRates();
                           if(!OrderModify(OrderTicket(), OrderOpenPrice(), 0.0, tp,0))
                           {
                              err=GetLastError();
                              if(err != ERR_NO_ERROR)
                                 printf("l=%d, err=%s",__LINE__,errMsg(err));
                           }
                        }
                     }
                  }
                  else // if(idx <= cBuy[i].maxidx)
                  {
                     if(OrderSelect(cBuy[i].gOrder[cBuy[i].maxidx].ticket,SELECT_BY_TICKET))
                     {
                        tp = OrderTakeProfit();
                        RefreshRates();
                        if(OrderSelect(ticket,SELECT_BY_TICKET))
                        {
                           if(!OrderModify(OrderTicket(), OrderOpenPrice(), 0.0, tp,0))
                           {
                              err=GetLastError();
                              if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                           }
                        }
                        else
                        {
                           err=GetLastError();
                           if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                        }
                     }
                     else
                     {
                        err=GetLastError();
                        if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                     }
                  }
               } // USETAKEPROFIT
            }
            else // ticket<0
            {
               err=GetLastError();
               if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
            }
         } // signal on
      }
      //+------------------------------------------------------------------+
      //| BUY                                                              |
      //+------------------------------------------------------------------+
   }

   if(TRADE_DIR != BUY_ONLY && !LockRapidSel)
   {
      //+------------------------------------------------------------------+
      //| SELL                                                             |
      //+------------------------------------------------------------------+
      for(i=0; i<CASCADES; i++)
      {
         signalon = false;
         if(cSel[i].maxidx < 0)
         {
            if(EA_MODE != NoNew_Finish && EA_MODE != NoTradeSellGrid)
            {
               if(Bid >= cSel[i].gOrder[0].price2entry)
               {
                  signalon = true;
                  lots     = cSel[i].gOrder[0].lots2entry;
                  idx      = 0;
               }
            }
         }
         else if(cSel[i].maxidx < C.escalation -1)
         {
            for(j=cSel[i].maxidx+1; j<C.escalation ; j++)
            {
               if(cSel[i].gOrder[j].openprice != 0.0)
                  continue;
               else if(Bid < cSel[i].gOrder[j].price2entry)
                  break;
               else if(Bid >= cSel[i].gOrder[j].price2entry &&
                       Bid <= cSel[i].gOrder[j].price2entry+SpreadPoints)
               {
                  signalon = true;
                  lots     = cSel[i].gOrder[j].lots2entry;
                  idx      = j;
                  break;
               }
            }
         }

         if(signalon)
         {
            magic    = MAGIC_BASE + EA_SEQ;
            cid=(int)ChartID();
            //string symbol=StringSubstr(_Symbol,0,1) + StringSubstr(_Symbol,3,1);
            //comment  = "S^" + IntegerToString(EA_SEQ) + SS + IntegerToString(i) + SS + IntegerToString(idx) + SS
            //           + _Symbol + SS + IntegerToString((int)MathMod((int)cid,1000));
            comment = getComment("S",EA_SEQ,i,idx);
            ticket = OrderSend(_Symbol,OP_SELL,lots,Bid,SLIPPAGE,0.0,0.0,comment,magic,0,COLORSEL);
            if(ticket >= 0)
            {
               ret = true;
               if(USETAKEPROFIT)
               {
                  if(idx > cSel[i].maxidx)
                  {
                     RefreshRates();
                     if(OrderSelect(ticket,SELECT_BY_TICKET))
                     {
                        openprice   = OrderOpenPrice();
                        tp          = NormalizeDouble(openprice - C.tp_offset,_Digits);
                        if(!OrderModify(OrderTicket(), openprice, 0.0, tp,0))
                        {
                           err=GetLastError();
                           if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                        }
                     }
                     else
                     {
                        err=GetLastError();
                        if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                     }

                     for(j=cSel[i].maxidx; j>=0; j--)
                     {
                        if(OrderSelect(cSel[i].gOrder[j].ticket,SELECT_BY_TICKET))
                        {
                           RefreshRates();
                           if(!OrderModify(OrderTicket(), OrderOpenPrice(), 0.0, tp,0))
                           {
                              err=GetLastError();
                              if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                           }
                        }
                        else
                        {
                           err=GetLastError();
                           if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                        }
                     }
                  }
                  else
                  {
                     if(OrderSelect(cSel[i].gOrder[cSel[i].maxidx].ticket,SELECT_BY_TICKET))
                     {
                        tp = OrderTakeProfit();
                        if(OrderSelect(ticket,SELECT_BY_TICKET))
                        {
                           RefreshRates();
                           if(!OrderModify(OrderTicket(), OrderOpenPrice(), 0.0, tp,0))
                           {
                              err=GetLastError();
                              if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                           }
                        }
                        else
                        {
                           err=GetLastError();
                           if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
                        }
                     }
                     else
                        PrintError(__LINE__);
                  }
               } // USETAKEPROFIT
            }
            else
            {
               err=GetLastError();
               if(err != ERR_NO_ERROR) printf("l=%d, err=%s",__LINE__,errMsg(err));
            } // ticket<0
         } // signal on
         //+------------------------------------------------------------------+
         //| SELL                                                             |
         //+------------------------------------------------------------------+
      }
   }
   else // if(TRADE_DIR == BUY_ONLY or LockRapidSel)
   {
   }

   return ret;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   string gvprefix="EA_SEQ-",gvname;

   if(SHOWMONITOR)
   {
      DeleteTableTradeSet();
      DeleteTableGridSet();
   }

   if(SHOWTPLINE)
      DeleteTPLine();

//printf("l=%d, SetPriceLot2Order()",__LINE__);
//SetPriceLot2Order();

   gvname = gvprefix + IntegerToString(EA_SEQ);
//if(GlobalVariableCheck(gvname)) GlobalVariableDel(gvname);

   printf("l=%d, reason=%s",__LINE__,GetOnDeinitReason(reason));

}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteTableTradeSet()
{
   DeleteObjectName(0,"Obj_Title_EA_SEQ");
   DeleteObjectName(0,"Obj_Title_EA_MODE");
   DeleteObjectName(0,"Obj_Title_TRADE_DIR");
   DeleteObjectName(0,"Obj_Title_CASCADE");
   DeleteObjectName(0,"Obj_Title_ESCALATION");
   DeleteObjectName(0,"Obj_Title_GRID_LEG");
   DeleteObjectName(0,"Obj_Title_tp_offset");
   DeleteObjectName(0,"Obj_Title_chartid");

   DeleteObjectName(0,"Obj_Content_EA_SEQ");
   DeleteObjectName(0,"Obj_Content_EA_MODE");
   DeleteObjectName(0,"Obj_Content_TRADE_DIR");
   DeleteObjectName(0,"Obj_Content_CASCADE");
   DeleteObjectName(0,"Obj_Content_ESCALATION");
   DeleteObjectName(0,"Obj_Content_GRID_LEG");
   DeleteObjectName(0,"Obj_Content_tp_offset");
   DeleteObjectName(0,"Obj_Content_chartid");
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteTableGridSet()
{
   int      i,j;
   string   str1,str2;

   for(i=0; i<CASCADES; i++)
   {
      str1 = IntegerToString(i);
      DeleteObjectName(0,"Obj_Title_GridSet_"+str1);
      DeleteObjectName(0,"Obj_Title_Grids_"+str1);
      DeleteObjectName(0,"Obj_Title_Lots_"+str1);
      DeleteObjectName(0,"Obj_Title_PL_"+str1);

      DeleteObjectName(0,"Obj_Title_Sum_Sel_"+str1);
      DeleteObjectName(0,"Obj_SumLots_Sel_"+str1);
      DeleteObjectName(0,"Obj_SumPL_Sel_"+str1);
      DeleteObjectName(0,"Obj_Title_Sum_Buy_"+str1);
      DeleteObjectName(0,"Obj_SumLots_Buy_"+str1);
      DeleteObjectName(0,"Obj_SumPL_Buy_"+str1);

      for(j=0; j<C.escalation ; j++)
      {
         str2 = IntegerToString(j);

         DeleteObjectName(0,"Obj_Title_Grids_Sel_"+str1+"_"+str2);
         //printf("l=%d, Delete %s",__LINE__,"Obj_Title_Grids_Sel_"+str1+"_"+str2);
         DeleteObjectName(0,"Obj_Lots_Sel_"+str1+"_"+str2);
         DeleteObjectName(0,"Obj_PL_Sel_"+str1+"_"+str2);
         DeleteObjectName(0,"Obj_Title_Grids_Buy_"+str1+"_"+str2);
         DeleteObjectName(0,"Obj_Lots_Buy_"+str1+"_"+str2);
         DeleteObjectName(0,"Obj_PL_Buy_"+str1+"_"+str2);
      }
   }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void PlotTableTradeSet(int &xdist,int &ydist)
{
   int   w_easeq,w_eamode,w_tdir,w_cascade,w_escalation,w_grid_leg,w_tp_offset,w_chartid,w_flots;
   color colorbg;

   w_easeq        = FontSize*6;
   w_eamode       = FontSize*14;
   w_tdir         = FontSize*10;
   w_cascade      = FontSize*5;
   w_escalation   = FontSize*5;
   w_grid_leg     = FontSize*5;
   w_tp_offset    = FontSize*10;
   w_chartid      = FontSize*6;
   w_flots        = FontSize*6;

   colorbg = clrDarkGreen;
   CreateObjContent(0,"Obj_Title_EA_SEQ","EASEQ",0,xdist,ydist,w_easeq,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,colorbg,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Title_EA_MODE","EA_MODE",0,xdist+w_easeq,ydist,w_eamode,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,colorbg,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Title_TRADE_DIR","T_DIR",0,xdist+w_easeq+w_eamode,ydist,w_tdir,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,colorbg,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Title_CASCADE","CAS",0,xdist+w_easeq+w_eamode+w_tdir,ydist,w_cascade,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,colorbg,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Title_ESCALATION","ESC",0,xdist+w_easeq+w_eamode+w_tdir+w_cascade,ydist,w_escalation,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,colorbg,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Title_GRID_LEG","LEG",0,xdist+w_easeq+w_eamode+w_tdir+w_cascade+w_escalation,ydist,w_grid_leg,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,colorbg,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Title_tp_offset","TP_OFFSET",0,xdist+w_eamode+w_easeq+w_tdir+w_cascade+w_escalation+w_grid_leg,ydist,w_tp_offset,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,colorbg,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Title_FLOTS","FLOTS",0,xdist+w_eamode+w_easeq+w_tdir+w_cascade+w_escalation+w_grid_leg+w_tp_offset,ydist,w_flots,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,colorbg,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Title_chartid","ChartID",0,xdist+w_eamode+w_easeq+w_tdir+w_cascade+w_escalation+w_grid_leg+w_tp_offset+w_flots,ydist,w_chartid,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,colorbg,COLORBORDER,FontSize,Font);

   ydist += FontHeight;

   CreateObjContent(0,"Obj_Content_EA_SEQ","",0,xdist,ydist,w_easeq,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,clrBlack,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Content_EA_MODE","",0,xdist+w_easeq,ydist,w_eamode,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,clrBlack,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Content_TRADE_DIR","",0,xdist+w_easeq+w_eamode,ydist,w_tdir,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,clrBlack,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Content_CASCADE","",0,xdist+w_easeq+w_eamode+w_tdir,ydist,w_cascade,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,clrBlack,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Content_ESCALATION","",0,xdist+w_easeq+w_eamode+w_tdir+w_cascade,ydist,w_escalation,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,clrBlack,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Content_GRID_LEG","",0,xdist+w_easeq+w_eamode+w_tdir+w_cascade+w_escalation,ydist,w_grid_leg,FontHeight,ALIGN_RIGHT,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,clrBlack,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Content_tp_offset","",0,xdist+w_eamode+w_easeq+w_tdir+w_cascade+w_escalation+w_grid_leg,ydist,w_tp_offset,FontHeight,ALIGN_RIGHT,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,clrBlack,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Content_FLOTS","",0,xdist+w_eamode+w_easeq+w_tdir+w_cascade+w_escalation+w_grid_leg+w_tp_offset,ydist,w_flots,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,clrBlack,COLORBORDER,FontSize,Font);
   CreateObjContent(0,"Obj_Content_chartid","",0,xdist+w_eamode+w_easeq+w_tdir+w_cascade+w_escalation+w_grid_leg+w_tp_offset+w_flots,ydist,w_chartid,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrWhite,clrBlack,COLORBORDER,FontSize,Font);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void PlotDataTradeSet()
{
   int      i;
   string   str,dir;
   double   netlot,balance=AccountBalance(), equity=AccountEquity(),accountprofit=AccountProfit();
   color    colorft=clrWhite;

   switch(EA_MODE)
   {
   case Trade:
      str = "Trade";
      colorft = clrLime;
      break;
   case NoTrade:
      str = "No Trade";
      colorft = clrRed;
      break;
   case NoNew_Finish:
      str = "No New, Finish";
      colorft = clrDarkGray;
      break;
   case NoTradeBuyGrid:
      str = "No Trade Buy Grid";
      colorft = clrDarkGray;
      break;
   case NoTradeSellGrid:
      str = "No Trade Sel Grid";
      colorft = clrDarkGray;
      break;
   default:
      break;
   }

   ObjectSetString(0,"Obj_Content_EA_SEQ",OBJPROP_TEXT,IntegerToString(EA_SEQ));
   ObjectSetString(0,"Obj_Content_EA_MODE",OBJPROP_TEXT,str);
   ObjectSetInteger(0,"Obj_Content_EA_MODE",OBJPROP_COLOR,colorft);
   switch(TRADE_DIR)
   {
   case 0:
      dir="BOTH";
      break;
   case 1:
      dir="BUY";
      break;
   case 2:
      dir="SELL";
      break;
   default:
      break;
   }
   ObjectSetString(0,"Obj_Content_TRADE_DIR",OBJPROP_TEXT,dir);
   ObjectSetString(0,"Obj_Content_CASCADE",OBJPROP_TEXT,IntegerToString(CASCADES));
   ObjectSetString(0,"Obj_Content_ESCALATION",OBJPROP_TEXT,IntegerToString(ESCALATION));

   netlot = 0.0;
   for(i=0; i<CASCADES; i++)
   {
      netlot += cBuy[i].lots - cSel[i].lots;
   }
   ObjectSetString(0,"Obj_Content_GRID_LEG",OBJPROP_TEXT,IntegerToString(GRID_LEG,0));
   ObjectSetString(0,"Obj_Content_tp_offset",OBJPROP_TEXT,IntegerToString(TP_OFFSET));
   long cid=ChartID();
   ObjectSetString(0,"Obj_Content_chartid",OBJPROP_TEXT,(int)cid,IntegerToString((int)MathMod((int)cid,1000)));
   ObjectSetString(0,"Obj_Content_FLOTS",OBJPROP_TEXT,FIRSTLOTS); //DoubleToString(FIRSTLOTS,2));
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void PlotTableGridSet(int &xdist,int &ydist)
{
   int      i,j,w,h;
   int      w_seq,w_lots,w_pl;
   string   str1, str2;
   color    colorft,colorbg;

   w           = 0;
   w_seq       = FontSize*5;
   w_lots      = FontSize*5;
   w_pl        = FontSize*8;

   for(i=0; i<CASCADES; i++)
   {
      //str1 = IntegerToString(i+1);
      str1 = IntegerToString(i);

      colorbg  = C'150,150,150';
      colorft  = clrBlack;
      CreateObjContent(0,"Obj_Title_GridSet_"+str1,"Grid"+str1,0,xdist,ydist,w,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);

      h = FontHeight;
      CreateObjContent(0,"Obj_Title_Grids_"+str1,"E",0,xdist,ydist+h,w_seq,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);
      CreateObjContent(0,"Obj_Title_Lots_"+str1,"Lots",0,xdist+w_seq,ydist+h,w_lots,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);
      CreateObjContent(0,"Obj_Title_PL_"+str1,"P/L",0,xdist+w_seq+w_lots,ydist+h,w_pl,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);

      h += FontHeight;
      colorbg  = C'25,0,0';
      colorft  = clrWhite;
      for(j=0; j<C.escalation ; j++)
      {
         str2 = IntegerToString(C.escalation -j-1);
         //printf("l=%d,%s",__LINE__,"Obj_Title_Grids_Sel_"+str1+"_"+str2);
         CreateObjContent(0,"Obj_Title_Grids_Sel_"+str1+"_"+str2,"S"+str2,0,xdist,ydist+h+(FontHeight*j),w_seq,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);
         CreateObjContent(0,"Obj_Lots_Sel_"+str1+"_"+str2,"",0,xdist+w_seq,ydist+h+(FontHeight*j),w_lots,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);
         CreateObjContent(0,"Obj_PL_Sel_"+str1+"_"+str2,"",0,xdist+w_seq+w_lots,ydist+h+(FontHeight*j),w_pl,FontHeight,ALIGN_RIGHT,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);
      }

      h += FontHeight*j;
      colorbg = C'50,0,0';
      CreateObjContent(0,"Obj_Title_Sum_Sel_"+str1,"-S-",0,xdist,ydist+h,w_seq,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);
      CreateObjContent(0,"Obj_SumLots_Sel_"+str1,"",0,xdist+w_seq,ydist+h,w_lots,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrCyan,colorbg,COLORBORDER,FontSize,Font);
      CreateObjContent(0,"Obj_SumPL_Sel_"+str1,"",0,xdist+w_seq+w_lots,ydist+h,w_pl,FontHeight,ALIGN_RIGHT,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrCyan,colorbg,COLORBORDER,FontSize,Font);

      h += FontHeight;
      colorbg = clrMidnightBlue;
      CreateObjContent(0,"Obj_Title_Sum_Buy_"+str1,"-B-",0,xdist,ydist+h,w_seq,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);
      CreateObjContent(0,"Obj_SumLots_Buy_"+str1,"",0,xdist+w_seq,ydist+h,w_lots,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrCyan,colorbg,COLORBORDER,FontSize,Font);
      CreateObjContent(0,"Obj_SumPL_Buy_"+str1,"",0,xdist+w_seq+w_lots,ydist+h,w_pl,FontHeight,ALIGN_RIGHT,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,clrCyan,colorbg,COLORBORDER,FontSize,Font);

      h += FontHeight;
      colorbg = C'0,0,50';
      for(j=0; j<C.escalation ; j++)
      {
         //str2 = IntegerToString(j+1);
         str2 = IntegerToString(j);
         CreateObjContent(0,"Obj_Title_Grids_Buy_"+str1+"_"+str2,"B"+str2,0,xdist,ydist+h+(FontHeight*j),w_seq,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);
         CreateObjContent(0,"Obj_Lots_Buy_"+str1+"_"+str2,"",0,xdist+w_seq,ydist+h+(FontHeight*j),w_lots,FontHeight,ALIGN_CENTER,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);
         CreateObjContent(0,"Obj_PL_Buy_"+str1+"_"+str2,"",0,xdist+w_seq+w_lots,ydist+h+(FontHeight*j),w_pl,FontHeight,ALIGN_RIGHT,true,CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,colorft,colorbg,COLORBORDER,FontSize,Font);
      }

      xdist += w_seq+w_lots+w_pl;
   }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void PlotDataGridSet()
{
   int      i,j;
   string   str1,str2;

   for(i=0; i<CASCADES; i++)
   {
      //str1 = IntegerToString(i+1);
      str1 = IntegerToString(i);

      if(cSel[i].lots != 0.0)
      {
         ObjectSetString(0,"Obj_SumLots_Sel_"+str1,OBJPROP_TEXT,DoubleToStr(cSel[i].lots,2));
         //ObjectSetString(0,"Obj_SumPL_Sel_"+str1,OBJPROP_TEXT,DoubleToStr(cSel[i].avgprice,_Digits));
         ObjectSetString(0,"Obj_SumPL_Sel_"+str1,OBJPROP_TEXT,DoubleToStr(cSel[i].pl,2));
      }
      else
      {
         ObjectSetString(0,"Obj_SumLots_Sel_"+str1,OBJPROP_TEXT,"");
         ObjectSetString(0,"Obj_SumPL_Sel_"+str1,OBJPROP_TEXT,"");
      }

      if(cBuy[i].lots != 0.0)
      {
         ObjectSetString(0,"Obj_SumLots_Buy_"+str1,OBJPROP_TEXT,DoubleToStr(cBuy[i].lots,2));
         //ObjectSetString(0,"Obj_SumPL_Buy_"+str1,OBJPROP_TEXT,DoubleToStr(cBuy[i].avgprice,_Digits));
         ObjectSetString(0,"Obj_SumPL_Buy_"+str1,OBJPROP_TEXT,DoubleToStr(cBuy[i].pl,2));
      }
      else
      {
         ObjectSetString(0,"Obj_SumLots_Buy_"+str1,OBJPROP_TEXT,"");
         ObjectSetString(0,"Obj_SumPL_Buy_"+str1,OBJPROP_TEXT,"");
      }

      for(j=0; j<C.escalation ; j++)
      {
         //str2 = IntegerToString(j+1);
         str2 = IntegerToString(j);

         if(cSel[i].gOrder[j].lots != 0.0)
         {
            ObjectSetString(0,"Obj_Lots_Sel_"+str1+"_"+str2,OBJPROP_TEXT,DoubleToStr(cSel[i].gOrder[j].lots,2));
            //ObjectSetString(0,"Obj_PL_Sel_"+str1+"_"+str2,OBJPROP_TEXT,DoubleToStr(cSel[i].gOrder[j].openprice,_Digits));
            ObjectSetString(0,"Obj_PL_Sel_"+str1+"_"+str2,OBJPROP_TEXT,DoubleToStr(cSel[i].gOrder[j].pl,2));
         }
         else
         {
            ObjectSetString(0,"Obj_Lots_Sel_"+str1+"_"+str2,OBJPROP_TEXT,"");
            ObjectSetString(0,"Obj_PL_Sel_"+str1+"_"+str2,OBJPROP_TEXT,"");
         }

         if(cBuy[i].gOrder[j].lots != 0.0)
         {
            ObjectSetString(0,"Obj_Lots_Buy_"+str1+"_"+str2,OBJPROP_TEXT,DoubleToStr(cBuy[i].gOrder[j].lots,2));
            //ObjectSetString(0,"Obj_PL_Buy_"+str1+"_"+str2,OBJPROP_TEXT,DoubleToStr(cBuy[i].gOrder[j].openprice,_Digits));
            ObjectSetString(0,"Obj_PL_Buy_"+str1+"_"+str2,OBJPROP_TEXT,DoubleToStr(cBuy[i].gOrder[j].pl,2));
         }
         else
         {
            ObjectSetString(0,"Obj_Lots_Buy_"+str1+"_"+str2,OBJPROP_TEXT,"");
            ObjectSetString(0,"Obj_PL_Buy_"+str1+"_"+str2,OBJPROP_TEXT,"");
         }
      }
   }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime TimeOffset(const datetime time, int offset)
{
   datetime    rt=NULL;
   int         sig,offsetadd=0;

   sig = (offset==0) ? 1 : offset/MathAbs(offset);
   if(time != NULL)
   {
      if(TimeDayOfWeek(time+offset) == 6)
         offsetadd = sig*86400*2;
      else if(TimeDayOfWeek(time+offset) == 0)
         offsetadd = sig*86400;

      rt = time + offset + offsetadd;
   }

   return rt;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CreateTPLine()
{
   int      i;
   double   p2buy=MAXVALUE,p2sel=MINVALUE;

   for(i=0; i<CASCADES; i++)
   {
      if(p2buy == MAXVALUE && cBuy[i].maxidx != -1)
      {
         if(cBuy[i].maxidx < ESCALATION-1)
            p2buy = cBuy[i].gOrder[cBuy[i].maxidx+1].price2entry;
         else
         {
            if(i < CASCADES-1)
            {
               if(cBuy[i+1].maxidx == -1)
                  p2buy = cBuy[i+1].gOrder[0].price2entry;
            }
         }
      }

      if(p2sel == MINVALUE && cSel[i].maxidx != -1)
      {
         if(cSel[i].maxidx < ESCALATION-1)
            p2sel = cSel[i].gOrder[cSel[i].maxidx+1].price2entry;
         else
         {
            if(i < CASCADES-1)
            {
               if(cSel[i+1].maxidx == -1)
                  p2sel = cSel[i+1].gOrder[0].price2entry;
            }
         }
      }

      if(!USETAKEPROFIT)
      {
         if(cBuy[i].price2close != MAXVALUE)
            CreateObjectHLine(0,"HLine_Price2CloseBuy"+"_"+IntegerToString(i+1),0,cBuy[i].price2close,1,clrMagenta,STYLE_DASHDOTDOT);

         if(cSel[i].price2close != MINVALUE)
            CreateObjectHLine(0,"HLine_Price2CloseSel"+"_"+IntegerToString(i+1),0,cSel[i].price2close,1,clrMagenta,STYLE_DASHDOTDOT);
      }
   }

   if(p2buy != MAXVALUE)
      CreateObjectHLine(0,"HLine_Price2Buy",0,p2buy,1,COLORBUY,STYLE_SOLID);

   if(p2sel != MINVALUE)
      CreateObjectHLine(0,"HLine_Price2Sel",0,p2sel,1,COLORSEL,STYLE_SOLID);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteTPLine()
{
   int   i;

   DeleteObjectName(0,"HLine_Price2Buy");
   DeleteObjectName(0,"HLine_Price2Sel");

   for(i=0; i<CASCADES; i++)
   {
      DeleteObjectName(0,"HLine_Price2CloseBuy"+"_"+IntegerToString(i+1));
      DeleteObjectName(0,"HLine_Price2CloseSel"+"_"+IntegerToString(i+1));
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ResizeGrid()
{
   int      i;

   if(ArrayResize(cBuy,CASCADES) != CASCADES)
      PrintError(__LINE__);

   if(ArrayResize(cSel,CASCADES) != CASCADES)
      PrintError(__LINE__);

   for(i=0; i<CASCADES; i++)
   {
      if(ArrayResize(cBuy[i].gOrder,C.escalation +1) != C.escalation +1)
         PrintError(__LINE__);

      if(ArrayResize(cSel[i].gOrder,C.escalation +1) != C.escalation +1)
         PrintError(__LINE__);
   }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseOrderBuy(int idx)
{
   int j, err;

   for(j=cBuy[idx].maxidx; j>=0; j--)
   {
      if(cBuy[idx].gOrder[j].ticket >= 0)
      {
         if(OrderSelect(cBuy[idx].gOrder[j].ticket,SELECT_BY_TICKET))
         {
            if(OrderClose(OrderTicket(),OrderLots(),Bid,SLIPPAGE,COLORCLOSEBUY))
               printf("l=%d, OrderClose BUY ticket=%d, lots=%.2f",__LINE__, OrderTicket(), OrderLots());
            else
            {
               err=GetLastError();
               if(err != ERR_NO_ERROR) printf("l=%d, ticket=%d, err=%s",__LINE__,OrderTicket(),errMsg(err));
            }
         }
         else
         {
            err=GetLastError();
            if(err != ERR_NO_ERROR) printf("l=%d, ticket=%d, err=%s",__LINE__,OrderTicket(),errMsg(err));
         }
      }
      else
         printf("l=%d, Error cBuy[%d].gOrder[%d].ticket=%d",__LINE__, idx, j, cBuy[idx].gOrder[j].ticket);
   }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseOrderSel(int idx)
{
   int j,err;

   for(j=cSel[idx].maxidx; j>=0; j--)
   {
      if(cSel[idx].gOrder[j].ticket >= 0)
      {
         if(OrderSelect(cSel[idx].gOrder[j].ticket,SELECT_BY_TICKET))
         {
            if(OrderClose(OrderTicket(),OrderLots(),Ask,SLIPPAGE,COLORCLOSESEL))
               printf("l=%d, OrderClose SELL ticket=%d, lots=%.2f",__LINE__, OrderTicket(), OrderLots());
            else
            {
               err=GetLastError();
               if(err != ERR_NO_ERROR) printf("l=%d, OrderClose ticket=%d, err=%s",__LINE__,OrderTicket(),errMsg(err));
            }
         }
         else
         {
            err=GetLastError();
            if(err != ERR_NO_ERROR) printf("l=%d, OrderSelect ticket=%d, err=%s",__LINE__,OrderTicket(),errMsg(err));
         }
      }
      else
         printf("l=%d, Error cSel[%d].gOrder[%d].ticket=%d",__LINE__, idx, j, cSel[idx].gOrder[j].ticket);
   } // for
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string getComment(string type, int ea_seq, int cascade, int idx)
{
   string comment;
   long cid = ChartID();
   comment  = type + SS + IntegerToString(ea_seq) + SS + IntegerToString(cascade) + SS + IntegerToString(idx) + SS
              + _Symbol + SS + IntegerToString((int)MathMod((int)cid,1000));
   return(comment);
}
//+------------------------------------------------------------------+
void pErr(int line, string errcase)
{
   int err=GetLastError();
   if(err != ERR_NO_ERROR) printf("l=%d, case=%s, err=%s", line, errcase, errMsg(err));
}