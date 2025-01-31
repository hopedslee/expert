//+------------------------------------------------------------------+
//|                                                  AccountInfo.mq4 |
//|                            Copyright ?2007, Alexander Enchevich |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright ?2007, Alexander Enchevich"
#property link      ""


//+------------------------------------------------------------------+
void PrintDynamicAccountInfo()
{
	Print( "AccountMargin : ",          AccountMargin ());         
	Print( "AccountFreeMargin : ",      AccountFreeMargin ());     
	Print( "AccountFreeMarginCheck, 1 Lot, Buy: ", AccountFreeMarginCheck (Symbol(), OP_BUY, 1));
	Print( "AccountFreeMarginCheck, 1 Lot, Sell : ", AccountFreeMarginCheck (Symbol(), OP_SELL, 1));
	Print( "AccountStopoutLevel : ",    AccountStopoutLevel ());   
	Print( "AccountEquity : ",          AccountEquity ());         
	Print( "AccountProfit : ",          AccountProfit ());         
	Print( "AccountBalance : ", 		AccountBalance ());        
	Print( "AccountCredit : ",          AccountCredit ());         

	Print( "Tick Value : ",          MarketInfo(Symbol(),MODE_TICKVALUE));         
	Print( "Tick Size : ",          MarketInfo(Symbol(),MODE_TICKSIZE));         
	printf( "Tick Size : %.5f",          MarketInfo(Symbol(),MODE_TICKSIZE));         
}
//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int init()
{
//----
	PrintDynamicAccountInfo();
	Print( "AccountCurrency : ",        AccountCurrency ());       
	Print( "AccountFreeMarginMode : ",  AccountFreeMarginMode ()); 
	Print( "  3 - only loss value is used for calculation, the current loss on open positions is not considered");
	Print( "  2 - only profit value is used for calculation, the current loss on open positions is not considered");
	Print( "  1 - both floating profit and loss on open positions on the current account are used for free margin calculation");
	Print( "  0 - floating profit/loss is not used for calculation");
	Print( "  AccountFreeMarginMode Legend:");
	Print( "AccountLeverage : ",        AccountLeverage ());       
	Print( "AccountStopoutMode : ",     AccountStopoutMode   ());  
	Print( "  1 - comparison of the free margin level to the absolute value");
	Print( "  0 - calculation of percentage ratio between free margin and equity");
	Print( "  AccountStopoutMode Legend:");
	Print( "AccountServer : ",          AccountServer ());         
	Print( "AccountCompany : ",         AccountCompany ());        
	Print( "AccountName : ",            AccountName ());           
	Print( "AccountNumber : ",          AccountNumber ());         
	Print( "Account StopOut Level : ", AccountStopoutLevel());
	double arm=MarketInfo(Symbol(),MODE_MARGINREQUIRED);
	Print( "Symbol() Required Margin : ", arm);
	DoubleToStr(Point,5);
    Print("MODE_SWAPLONG : ", DoubleToStr(MarketInfo(Symbol(),MODE_SWAPLONG),4));
    Print("MODE_SWAPSHORT : ",DoubleToStr(MarketInfo(Symbol(),MODE_SWAPSHORT),4));

    Print("SPREAD : ",DoubleToStr(MarketInfo(Symbol(),MODE_SPREAD),1));

    
    double Gap=MarketInfo(Symbol(),MODE_STOPLEVEL);
    printf("STOPLEVEL=%.f",Gap);
    double digits=MarketInfo(Symbol(),MODE_DIGITS);
    printf("DIGITS=%.f",digits);
    double p=DoubleToString(Point,Digits);
    printf("POINT=%.5f",p);
    
//----
	return(0);
}
