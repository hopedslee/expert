//+------------------------------------------------------------------+
//|                                                         swap.mq4 |
//|                                  Copyright 2023, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
//#property show_inputs

string sym[]={"GBPJPY","GBPCAD","EURUSD","GBPUSD","USDCAD","AUDNZD","AUDJPY","CADJPY","AUDCAD","USDJPY","AUDUSD","EURGBP"};
//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+

void OnStart()
  {
//---
   for(int i=11; i>=0; i--)
   {
      //printf("i=%d",i);
      StringToUpper(sym[i]);
      printf("%s|%.02f|%.02f", sym[i],MarketInfo(sym[i],MODE_SWAPLONG), MarketInfo(sym[i],MODE_SWAPSHORT) );
   }
  }
//+------------------------------------------------------------------+
// AAA BBB CCC
