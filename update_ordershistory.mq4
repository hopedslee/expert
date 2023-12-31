//+------------------------------------------------------------------+
//|                                                symbol_profit.mq4 |
//|                                  Copyright 2023, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

extern   int      FROM_DAYS_BEFORE=1; //0-today,1-day before,7-week before
bool check=FALSE;
string domain1="139.150.64.222";
string update_history="fx/updator/update_history.php";
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }

int i=0;
double servertime=Hour()+(Minute()*0.01);
int dow = DayOfWeek();
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   string symbol="";
   double profit=0;
  
   if(i++<1)
   {
      update_oh();
   }
   else ExpertRemove();
}    

void update_oh()
{
   bool record=False;
   string cookie=NULL,headers;
   char post[],result[];
   int ret;
   string url="";
   int timeout=5000;

   double lots=0;
   double deposit=0, withdrawal=0, profit=0;

   // OrdersHistory 테이블 갱신
   // 1 2  3 4  5
   // 월,화,수,목,금
   //if( ((dow>0) && (servertime>23.50 && servertime<23.59)) || HISTORYUPDATE)
   if( ((dow>0) && (servertime>9.05 && servertime<9.59)))
     {
      // update and/or insert OrdersHistory
      int total=OrdersHistoryTotal();
      printf("l=%d, total=%d",__LINE__,total);
      for(int c=0; c<total; c++)
        {
         if(OrderSelect(c,SELECT_BY_POS,MODE_HISTORY))
           {
            string ordertype="";
            //printf("l=%d, Ticket=%d",__LINE__,OrderTicket());
            switch(OrderType())
              {
               case 0:
                  ordertype="buy";
                  record=True;
                  break;
               case 1:
                  ordertype="sell";
                  record=True;
                  break;
               case 2:
                  ordertype="buylimit";
                  record=False;
                  break;
               case 3:
                  ordertype="selllimit";
                  record=False;
                  break;
               case 4:
                  ordertype="buystop";
                  record=False;
                  break;
               case 5:
                  ordertype="sellstop";
                  record=False;
                  break;
               default:
                  record=False;
                  break;
              }

            if(OrderType()>5)
              {
               lots=0;
               if(OrderProfit()<0)
                 {
                  deposit=0;
                  withdrawal=OrderProfit()*(-1);
                 }
               else
                 {
                  deposit=OrderProfit();
                  withdrawal=0;
                 }
               //printf("l=%d, ot=%d, withdrawal=%.1f",__LINE__,OrderType(),withdrawal);
               profit=0;
              }
            else
              {

               deposit=0;
               withdrawal=0;
               profit=OrderProfit();
               lots=OrderLots();
              }

            string message = StringFormat("%d|%d|%s|%s|%.2f|%s|%f|%f|%f|%s|%f|%.1f|%.1f|%.1f|%.1f|%.1f|%d|%s",
                                          AccountNumber(),   //0
                                          OrderTicket(),     //1
                                          OrderSymbol(),     //2
                                          ordertype,         //3
                                          lots,              //4

                                          TimeToStr(OrderOpenTime(),TIME_DATE|TIME_SECONDS),  //5
                                          OrderOpenPrice(),  //6
                                          OrderStopLoss(),   //7
                                          OrderTakeProfit(), //8domain1
                                          
                                          TimeToStr(OrderCloseTime(),TIME_DATE|TIME_SECONDS), //9

                                          OrderClosePrice(), //10
                                          deposit,           //11
                                          withdrawal,        //12
                                          profit,            //13
                                          OrderSwap(),       //14

                                          OrderCommission(), //15
                                          OrderMagicNumber(),//16
                                          StringTrimRight(OrderComment())     //17
                                         );
            if(record) {
            url=StringFormat("http://%s/%s?message=%s", domain1, update_history, message);
            ret=WebRequest("GET",url,cookie,NULL,timeout,post,0,result,headers);
            string msg=CharArrayToString(result,0);
            printf("l=%d, servertime=%.2f, url=%s, msg=%s",__LINE__, servertime, url, msg);
            }

           } // order select
        } // for
     }
   return;
  }