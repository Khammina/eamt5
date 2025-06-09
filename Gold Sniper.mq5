//+------------------------------------------------------------------+
//|                                                   Gold Sniper.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   4

// TMA Bands
#property indicator_label1  "TMA Upper"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrWhite
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "TMA Lower"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrWhite
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "TMA Upper Outer"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "TMA Lower Outer"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrYellow
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

// Input parameters
input bool    trend_mode = false;         // Trend Mode
input bool    Zone = false;               // Zone
input bool    stoch_sig = true;           // Stochastic Signals
input bool    divergen_sig = true;        // Divergence Signals
input bool    hidden_sig = true;          // Hidden Divergence Signals
input int     HalfLength = 56;            // TMA Half Length
input int     AtrPeriod = 100;            // ATR Period
input double  AtrMultiplier = 2.5;        // ATR Multiplier Inner
input double  AtrMultiplier_2 = 4.5;      // ATR Multiplier Outer
input double  TMAangle = 4.0;             // TMA Angle
input color   colorBands = clrWhite;      // Inner Bands Color
input color   colorBands_2 = clrYellow;   // Outer Bands Color

// Indicator buffers
double TMAUpper[];
double TMALower[];
double TMAUpperOuter[];
double TMALowerOuter[];
double TMAMiddle[];
double ATRBuffer[];

// Technical indicator handles
int StochasticHandle;
int RSIHandle;
int DMIHandle;
int CCIHandle;
int EMAHandle;
int MACDHandle;
int SMA100Handle;
int SMA200Handle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set indicator buffers
    SetIndexBuffer(0, TMAUpper, INDICATOR_DATA);
    SetIndexBuffer(1, TMALower, INDICATOR_DATA);
    SetIndexBuffer(2, TMAUpperOuter, INDICATOR_DATA);
    SetIndexBuffer(3, TMALowerOuter, INDICATOR_DATA);
    SetIndexBuffer(4, TMAMiddle, INDICATOR_CALCULATIONS);
    SetIndexBuffer(5, ATRBuffer, INDICATOR_CALCULATIONS);
    
    // Initialize technical indicators
    StochasticHandle = iStochastic(_Symbol, PERIOD_CURRENT, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
    RSIHandle = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
    DMIHandle = iADX(_Symbol, PERIOD_CURRENT, 14);
    CCIHandle = iCCI(_Symbol, PERIOD_CURRENT, 14, PRICE_TYPICAL);
    EMAHandle = iMA(_Symbol, PERIOD_CURRENT, 6, 0, MODE_EMA, PRICE_CLOSE);
    MACDHandle = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
    SMA100Handle = iMA(_Symbol, PERIOD_H1, 100, 0, MODE_SMA, PRICE_CLOSE);
    SMA200Handle = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_SMA, PRICE_CLOSE);
    
    if(StochasticHandle == INVALID_HANDLE || RSIHandle == INVALID_HANDLE || 
       DMIHandle == INVALID_HANDLE || CCIHandle == INVALID_HANDLE ||
       EMAHandle == INVALID_HANDLE || MACDHandle == INVALID_HANDLE ||
       SMA100Handle == INVALID_HANDLE || SMA200Handle == INVALID_HANDLE)
    {
        Print("Failed to create indicator handles");
        return INIT_FAILED;
    }
    
    // Set drawing styles
    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
    PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_LINE);
    PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_LINE);
    PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_LINE);
    
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, colorBands);
    PlotIndexSetInteger(1, PLOT_LINE_COLOR, colorBands);
    PlotIndexSetInteger(2, PLOT_LINE_COLOR, colorBands_2);
    PlotIndexSetInteger(3, PLOT_LINE_COLOR, colorBands_2);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(StochasticHandle);
    IndicatorRelease(RSIHandle);
    IndicatorRelease(DMIHandle);
    IndicatorRelease(CCIHandle);
    IndicatorRelease(EMAHandle);
    IndicatorRelease(MACDHandle);
    IndicatorRelease(SMA100Handle);
    IndicatorRelease(SMA200Handle);
}

//+------------------------------------------------------------------+
//| Get weighted price                                               |
//+------------------------------------------------------------------+
double GetPrice(int shift)
{
    if(shift >= Bars(_Symbol, PERIOD_CURRENT))
        return 0.0;
        
    double high_val = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double low_val = iLow(_Symbol, PERIOD_CURRENT, shift);
    double close_val = iClose(_Symbol, PERIOD_CURRENT, shift);
    
    if(high_val <= 0 || low_val <= 0 || close_val <= 0)
        return 0.0;
        
    return (high_val + low_val + close_val + close_val) / 4.0;
}

//+------------------------------------------------------------------+
//| Calculate ATR manually                                           |
//+------------------------------------------------------------------+
double CalculateATR(int shift)
{
    // Ensure we have enough bars
    if(shift + AtrPeriod + 15 >= Bars(_Symbol, PERIOD_CURRENT))
        return 0.0;
        
    double atr = 0.0;
    for(int j = 0; j < AtrPeriod; j++)
    {
        int bar_index = shift + j + 10;
        if(bar_index + 1 >= Bars(_Symbol, PERIOD_CURRENT))
            continue;
            
        double high1 = iHigh(_Symbol, PERIOD_CURRENT, bar_index);
        double low1 = iLow(_Symbol, PERIOD_CURRENT, bar_index);
        double close1 = iClose(_Symbol, PERIOD_CURRENT, bar_index + 1);
        
        if(high1 > 0 && low1 > 0 && close1 > 0)
            atr += MathMax(high1, close1) - MathMin(low1, close1);
    }
    return atr / AtrPeriod;
}

//+------------------------------------------------------------------+
//| Calculate TMA                                                    |
//+------------------------------------------------------------------+
double CalculateTMA(int shift)
{
    // Ensure we have enough bars
    if(shift + HalfLength >= Bars(_Symbol, PERIOD_CURRENT))
        return 0.0;
        
    double price_center = GetPrice(shift);
    if(price_center <= 0) return 0.0;
    
    double sum = (HalfLength + 1) * price_center;
    double sumw = (HalfLength + 1);
    int k = HalfLength;
    
    for(int j = 1; j <= HalfLength; j++)
    {
        double price_forward = GetPrice(shift + j);
        if(price_forward > 0)
        {
            sum += k * price_forward;
            sumw += k;
        }
        
        if(j <= shift)
        {
            double price_backward = GetPrice(shift - j);
            if(price_backward > 0)
            {
                sum += k * price_backward;
                sumw += k;
            }
        }
        k--;
    }
    
    return sumw > 0 ? sum / sumw : 0.0;
}

//+------------------------------------------------------------------+
//| Check stochastic signals                                         |
//+------------------------------------------------------------------+
bool CheckStochasticSignals(int shift, bool &bullish, bool &bearish)
{
    double k_main[3], d_signal[3], rsi[3], macd_main[3], macd_signal[3], sma100[2], sma200[2];
    
    // Reset signals
    bullish = false;
    bearish = false;
    
    if(CopyBuffer(StochasticHandle, 0, shift, 3, k_main) < 3 ||
       CopyBuffer(StochasticHandle, 1, shift, 3, d_signal) < 3 ||
       CopyBuffer(RSIHandle, 0, shift, 3, rsi) < 3 ||
       CopyBuffer(MACDHandle, 0, shift, 3, macd_main) < 3 ||
       CopyBuffer(MACDHandle, 1, shift, 3, macd_signal) < 3)
        return false;
    
    double hist = macd_main[1] - macd_signal[1];
    
    // Check for crossovers
    bool k_cross_above_d = (k_main[1] > d_signal[1] && k_main[2] <= d_signal[2]);
    bool k_cross_below_d = (k_main[1] < d_signal[1] && k_main[2] >= d_signal[2]);
    
    if(trend_mode)
    {
        if(CopyBuffer(SMA100Handle, 0, shift, 2, sma100) < 2 ||
           CopyBuffer(SMA200Handle, 0, shift, 2, sma200) < 2)
            return false;
            
        bullish = (k_cross_above_d && rsi[1] < 50 && k_main[1] < 20 && hist < -0.5 && sma100[0] > sma200[0]);
        bearish = (k_cross_below_d && rsi[1] > 50 && k_main[1] > 80 && hist > 0.5 && sma100[0] < sma200[0]);
    }
    else
    {
        bullish = (k_cross_above_d && rsi[1] < 50 && k_main[1] < 20 && hist < -0.5);
        bearish = (k_cross_below_d && rsi[1] > 50 && k_main[1] > 80 && hist > 0.5);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check divergence signals                                         |
//+------------------------------------------------------------------+
bool CheckDivergenceSignals(int shift, bool &bullish, bool &bearish)
{
    // Reset signals
    bullish = false;
    bearish = false;
    
    // Need enough bars for divergence analysis
    if(shift < 60) return false;
    
    double rsi[61];
    if(CopyBuffer(RSIHandle, 0, shift, 61, rsi) < 61)
        return false;
    
    // Look for pivot points in RSI and price
    int pivot_bars = 5;
    bool rsi_higher_low = false, price_lower_low = false;
    bool rsi_lower_high = false, price_higher_high = false;
    
    // Find recent pivot lows for bullish divergence
    for(int i = pivot_bars + 5; i < 55; i++)
    {
        bool is_pivot_low = true;
        for(int j = 1; j <= pivot_bars; j++)
        {
            if(rsi[i] >= rsi[i-j] || rsi[i] >= rsi[i+j])
            {
                is_pivot_low = false;
                break;
            }
        }
        
        if(is_pivot_low)
        {
            // Check for higher low in RSI and lower low in price
            double current_low = iLow(_Symbol, PERIOD_CURRENT, shift + pivot_bars);
            double prev_low = iLow(_Symbol, PERIOD_CURRENT, shift + i);
            
            if(current_low != 0 && prev_low != 0 && 
               rsi[pivot_bars] > rsi[i] && current_low < prev_low)
            {
                rsi_higher_low = true;
                price_lower_low = true;
                break;
            }
        }
    }
    
    // Find recent pivot highs for bearish divergence
    for(int i = pivot_bars + 5; i < 55; i++)
    {
        bool is_pivot_high = true;
        for(int j = 1; j <= pivot_bars; j++)
        {
            if(rsi[i] <= rsi[i-j] || rsi[i] <= rsi[i+j])
            {
                is_pivot_high = false;
                break;
            }
        }
        
        if(is_pivot_high)
        {
            // Check for lower high in RSI and higher high in price
            double current_high = iHigh(_Symbol, PERIOD_CURRENT, shift + pivot_bars);
            double prev_high = iHigh(_Symbol, PERIOD_CURRENT, shift + i);
            
            if(current_high != 0 && prev_high != 0 && 
               rsi[pivot_bars] < rsi[i] && current_high > prev_high)
            {
                rsi_lower_high = true;
                price_higher_high = true;
                break;
            }
        }
    }
    
    if(trend_mode)
    {
        double sma100[2], sma200[2];
        if(CopyBuffer(SMA100Handle, 0, shift, 2, sma100) < 2 ||
           CopyBuffer(SMA200Handle, 0, shift, 2, sma200) < 2)
            return false;
            
        bullish = rsi_higher_low && price_lower_low && sma100[0] > sma200[0];
        bearish = rsi_lower_high && price_higher_high && sma100[0] < sma200[0];
    }
    else
    {
        bullish = rsi_higher_low && price_lower_low;
        bearish = rsi_lower_high && price_higher_high;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    // Ensure we have enough data
    if(rates_total < HalfLength + AtrPeriod + 20)
        return 0;
    
    int start = prev_calculated > 0 ? prev_calculated - 1 : HalfLength + AtrPeriod + 15;
    if(start >= rates_total) start = rates_total - 1;
    
    for(int i = start; i < rates_total && i >= 0; i++)
    {
        int shift = rates_total - 1 - i;
        
        // Skip if not enough historical data
        if(shift + HalfLength + AtrPeriod + 15 >= rates_total)
        {
            TMAUpper[i] = 0;
            TMALower[i] = 0;
            TMAUpperOuter[i] = 0;
            TMALowerOuter[i] = 0;
            TMAMiddle[i] = 0;
            ATRBuffer[i] = 0;
            continue;
        }
        
        // Calculate ATR
        ATRBuffer[i] = CalculateATR(shift);
        if(ATRBuffer[i] <= 0) continue;
        
        // Calculate TMA middle
        TMAMiddle[i] = CalculateTMA(shift);
        if(TMAMiddle[i] <= 0) continue;
        
        // Calculate TMA bands
        TMAUpper[i] = TMAMiddle[i] + AtrMultiplier * ATRBuffer[i];
        TMALower[i] = TMAMiddle[i] - AtrMultiplier * ATRBuffer[i];
        
        TMAUpperOuter[i] = TMAMiddle[i] + AtrMultiplier_2 * ATRBuffer[i];
        TMALowerOuter[i] = TMAMiddle[i] - AtrMultiplier_2 * ATRBuffer[i];
        
        // Signal detection logic remains but no arrows are drawn
        if(i >= rates_total - 100 && shift >= 60)
        {
            bool bullish_stoch = false, bearish_stoch = false;
            bool bullish_div = false, bearish_div = false;
            
            if(stoch_sig)
                CheckStochasticSignals(shift, bullish_stoch, bearish_stoch);
            
            if(divergen_sig)
                CheckDivergenceSignals(shift, bullish_div, bearish_div);
            
            // Note: Signal detection remains active but no visual arrows are drawn
        }
    }
    
    return rates_total;
}
