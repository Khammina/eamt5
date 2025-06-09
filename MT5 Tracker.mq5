//+------------------------------------------------------------------+
//|                            Enhanced_MT5_Discord_Telegram_Tracker.mq5 |
//|                                                   Trade Tracker EA |
//|                                    Sends alerts to Discord & Telegram |
//+------------------------------------------------------------------+
#property copyright "Enhanced Trade Tracker EA"
#property version   "3.00"
#property strict

// Input parameters
input string DiscordWebhookURL = "https://discord.com/api/webhooks/1376805063191957514/tc0kMuoEI4clgSS_oYwSCrvCkyuVKfDF9ySR1Dz8NFhK_LV7x7FSeDauHlKRIDAkREzH"; // Discord Webhook URL
input string TelegramBotToken = "7165263301:AAGAVwbK938E3WXuqpFQAl1P9RoWrAHm52s"; // Telegram Bot Token
input string TelegramChatID = "6501082183"; // Telegram Chat ID
input bool EnableDiscordAlerts = true; // Enable Discord notifications
input bool EnableTelegramAlerts = true; // Enable Telegram notifications
input bool EnableTradeAlerts = true; // Enable trade open/close alerts
input bool EnableModifyAlerts = true; // Enable SL/TP modify alerts
input bool EnableDailySummary = true; // Enable daily P/L summary
input string SummaryTime = "23:59"; // Daily summary time (HH:MM)
input bool EnableSounds = true; // Enable sound notifications
input string BotName = "SMC Hybrid"; // Bot display name
input bool EnableDetailedMessages = true; // Enable detailed formatting
input int MessageRetryAttempts = 3; // Number of retry attempts for failed messages

// Global variables
datetime lastSummaryDate = 0;
double dayStartBalance = 0;
int totalPositions = 0;
ulong trackedPositions[];
double trackedSL[];
double trackedTP[];
datetime lastMessageTime = 0;
int messageCount = 0;
int telegramMessageCount = 0;

// Structure for tracking position data
struct PositionData
{
    ulong ticket;
    string symbol;
    double volume;
    double openPrice;
    double sl;
    double tp;
    ENUM_POSITION_TYPE type;
    datetime openTime;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Validate Discord settings
    if(EnableDiscordAlerts && DiscordWebhookURL == "")
    {
        Alert("❌ Discord Webhook URL is required when Discord alerts are enabled!");
        return INIT_FAILED;
    }
    
    if(EnableDiscordAlerts && StringFind(DiscordWebhookURL, "discord.com/api/webhooks/") == -1)
    {
        Alert("❌ Invalid Discord Webhook URL format!");
        return INIT_FAILED;
    }
    
    // Validate Telegram settings
    if(EnableTelegramAlerts && (TelegramBotToken == "" || TelegramChatID == ""))
    {
        Alert("❌ Telegram Bot Token and Chat ID are required when Telegram alerts are enabled!");
        return INIT_FAILED;
    }
    
    // Check if at least one notification method is enabled
    if(!EnableDiscordAlerts && !EnableTelegramAlerts)
    {
        Alert("❌ At least one notification method (Discord or Telegram) must be enabled!");
        return INIT_FAILED;
    }
    
    // Initialize daily tracking
    dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    lastSummaryDate = TimeCurrent();
    
    // Get current positions for tracking
    InitializePositionTracking();
    
    Print("Enhanced MT5 Discord & Telegram Tracker initialized successfully");
    
    // Send startup message
    string startMessage = "*MT5 Trade Tracker Started*\n";
    startMessage += "Account: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\n";
    startMessage += "Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
    startMessage += "Discord: " + (EnableDiscordAlerts ? "✅" : "❌") + "\n";
    startMessage += "Telegram: " + (EnableTelegramAlerts ? "✅" : "❌") + "\n";
    startMessage += "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n";
    startMessage += "─────────────────────────";
    
    SendNotification(startMessage);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    string stopMessage = "*MT5 Trade Tracker Stopped*\n";
    stopMessage += "Reason: " + GetUninitReasonText(reason) + "\n";
    stopMessage += "Discord Messages: " + IntegerToString(messageCount) + "\n";
    stopMessage += "Telegram Messages: " + IntegerToString(telegramMessageCount) + "\n";
    stopMessage += "Runtime: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n";
    stopMessage += "─────────────────────────";
    
    SendNotification(stopMessage);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    static datetime lastCheck = 0;
    
    // Throttle checks to prevent spam (check every second)
    if(TimeCurrent() - lastCheck < 1) return;
    lastCheck = TimeCurrent();
    
    CheckNewPositions();
    CheckPositionModifications();
    CheckClosedPositions();
    CheckDailySummary();
}

//+------------------------------------------------------------------+
//| Initialize position tracking arrays                              |
//+------------------------------------------------------------------+
void InitializePositionTracking()
{
    int positions = PositionsTotal();
    ArrayResize(trackedPositions, positions);
    ArrayResize(trackedSL, positions);
    ArrayResize(trackedTP, positions);
    
    totalPositions = 0;
    
    for(int i = 0; i < positions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            trackedPositions[totalPositions] = ticket;
            trackedSL[totalPositions] = PositionGetDouble(POSITION_SL);
            trackedTP[totalPositions] = PositionGetDouble(POSITION_TP);
            totalPositions++;
        }
    }
    
    ArrayResize(trackedPositions, totalPositions);
    ArrayResize(trackedSL, totalPositions);
    ArrayResize(trackedTP, totalPositions);
}

//+------------------------------------------------------------------+
//| Check for new positions                                          |
//+------------------------------------------------------------------+
void CheckNewPositions()
{
    int currentPositions = PositionsTotal();
    
    if(currentPositions > totalPositions)
    {
        // Find new positions
        for(int i = 0; i < currentPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionSelectByTicket(ticket))
            {
                // Check if this is a new position
                bool isNew = true;
                for(int j = 0; j < totalPositions; j++)
                {
                    if(trackedPositions[j] == ticket)
                    {
                        isNew = false;
                        break;
                    }
                }
                
                if(isNew && EnableTradeAlerts)
                {
                    SendTradeOpenAlert(ticket);
                    if(EnableSounds) PlaySound("alert.wav");
                    Sleep(500); // Small delay to prevent rapid-fire alerts
                }
            }
        }
        
        // Update tracking arrays
        InitializePositionTracking();
    }
}

//+------------------------------------------------------------------+
//| Check for position modifications                                 |
//+------------------------------------------------------------------+
void CheckPositionModifications()
{
    if(!EnableModifyAlerts) return;
    
    for(int i = 0; i < totalPositions; i++)
    {
        if(PositionSelectByTicket(trackedPositions[i]))
        {
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);
            string symbol = PositionGetString(POSITION_SYMBOL);
            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            
            bool slChanged = MathAbs(currentSL - trackedSL[i]) > SymbolInfoDouble(symbol, SYMBOL_POINT);
            bool tpChanged = MathAbs(currentTP - trackedTP[i]) > SymbolInfoDouble(symbol, SYMBOL_POINT);
            
            if(slChanged || tpChanged)
            {
                SendPositionModifyAlert(trackedPositions[i], trackedSL[i], trackedTP[i], currentSL, currentTP);
                trackedSL[i] = currentSL;
                trackedTP[i] = currentTP;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for closed positions                                       |
//+------------------------------------------------------------------+
void CheckClosedPositions()
{
    int currentPositions = PositionsTotal();
    
    if(currentPositions < totalPositions)
    {
        // Check recent history for closed trades
        datetime fromTime = TimeCurrent() - 300; // Last 5 minutes
        if(HistorySelect(fromTime, TimeCurrent()))
        {
            int deals = HistoryDealsTotal();
            for(int i = deals - 1; i >= 0; i--)
            {
                ulong dealTicket = HistoryDealGetTicket(i);
                if(dealTicket > 0)
                {
                    ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
                    datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
                    
                    // Only process recent exit deals
                    if(dealEntry == DEAL_ENTRY_OUT && dealTime > TimeCurrent() - 60 && EnableTradeAlerts)
                    {
                        SendTradeCloseAlert(dealTicket);
                        if(EnableSounds) 
                        {
                            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                            if(profit > 0)
                                PlaySound("ok.wav");
                            else
                                PlaySound("timeout.wav");
                        }
                        Sleep(500); // Prevent spam
                    }
                }
            }
        }
        
        // Update tracking
        InitializePositionTracking();
    }
}

//+------------------------------------------------------------------+
//| Send trade open alert                                            |
//+------------------------------------------------------------------+
void SendTradeOpenAlert(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);
    datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    string typeEmoji = (type == POSITION_TYPE_BUY) ? "📈" : "📉";
    string typeStr = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
    
    // Create message for both platforms
    string discordMessage = "**NEW POSITION OPENED**\n";
    discordMessage += "**Symbol:** " + symbol + "\n";
    discordMessage += "**Type:** **" + typeStr + "**\n";
    discordMessage += "**Volume:** " + DoubleToString(volume, 2) + "\n";
    discordMessage += "**Open Price:** " + DoubleToString(openPrice, digits) + "\n";
    
    if(sl > 0)
        discordMessage += "**Stop Loss:** " + DoubleToString(sl, digits) + "\n";
    else
        discordMessage += "**Stop Loss:** 0.00\n";
        
    if(tp > 0)
        discordMessage += "**Take Profit:** " + DoubleToString(tp, digits) + "\n";
    else
        discordMessage += "**Take Profit:** 0.00\n";
        
    discordMessage += "**Ticket:** " + IntegerToString(ticket) + "\n";
    discordMessage += "-----------------------------";
    
    // Telegram message (with emojis and markdown)
    string telegramMessage = typeEmoji + " *NEW POSITION OPENED*\n\n";
    telegramMessage += "*Symbol:* " + symbol + "\n";
    telegramMessage += "*Type:* *" + typeStr + "*\n";
    telegramMessage += "*Volume:* " + DoubleToString(volume, 2) + "\n";
    telegramMessage += "*Open Price:* " + DoubleToString(openPrice, digits) + "\n";
    
    if(sl > 0)
        telegramMessage += "*Stop Loss:* " + DoubleToString(sl, digits) + "\n";
    else
        telegramMessage += "*Stop Loss:* 0.00\n";
        
    if(tp > 0)
        telegramMessage += "*Take Profit:* " + DoubleToString(tp, digits) + "\n";
    else
        telegramMessage += "*Take Profit:* 0.00\n";
        
    telegramMessage += "*Ticket:* " + IntegerToString(ticket) + "\n";
    telegramMessage += "*Time:* " + TimeToString(openTime, TIME_SECONDS) + "\n";
    telegramMessage += "─────────────────────────";
    
    // Send to both platforms
    if(EnableDiscordAlerts) SendDiscordMessage(discordMessage);
    if(EnableTelegramAlerts) SendTelegramMessage(telegramMessage);
}

//+------------------------------------------------------------------+
//| Send position modify alert                                        |
//+------------------------------------------------------------------+
void SendPositionModifyAlert(ulong ticket, double oldSL, double oldTP, double newSL, double newTP)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    // Discord message
    string discordMessage = "**POSITION MODIFIED**\n";
    discordMessage += "**Symbol:** " + symbol + "\n";
    
    // Telegram message
    string telegramMessage = "*POSITION MODIFIED*\n\n";
    telegramMessage += "*Symbol:* " + symbol + "\n";
    
    if(MathAbs(newSL - oldSL) > SymbolInfoDouble(symbol, SYMBOL_POINT))
    {
        string slDiscord = "**Stop Loss:** ";
        string slTelegram = "*Stop Loss:* ";
        
        if(oldSL > 0) {
            slDiscord += DoubleToString(oldSL, digits);
            slTelegram += DoubleToString(oldSL, digits);
        } else {
            slDiscord += "0.00";
            slTelegram += "0.00";
        }
        
        slDiscord += " => ";
        slTelegram += "=> ";
        
        if(newSL > 0) {
            slDiscord += DoubleToString(newSL, digits);
            slTelegram += DoubleToString(newSL, digits);
        } else {
            slDiscord += "0.00";
            slTelegram += "0.00";
        }
        
        discordMessage += slDiscord + "\n";
        telegramMessage += slTelegram + "\n";
    }
    
    if(MathAbs(newTP - oldTP) > SymbolInfoDouble(symbol, SYMBOL_POINT))
    {
        string tpDiscord = "**Take Profit:** ";
        string tpTelegram = "*Take Profit:* ";
        
        if(oldTP > 0) {
            tpDiscord += DoubleToString(oldTP, digits);
            tpTelegram += DoubleToString(oldTP, digits);
        } else {
            tpDiscord += "0.00";
            tpTelegram += "0.00";
        }
        
        tpDiscord += " => ";
        tpTelegram += " => ";
        
        if(newTP > 0) {
            tpDiscord += DoubleToString(newTP, digits);
            tpTelegram += DoubleToString(newTP, digits);
        } else {
            tpDiscord += "0.00";
            tpTelegram += "0.00";
        }
        
        discordMessage += tpDiscord + "\n";
        telegramMessage += tpTelegram + "\n";
    }
    
    discordMessage += "**Ticket:** " + IntegerToString(ticket) + "\n";
    discordMessage += "-----------------------------";
    
    telegramMessage += "*Ticket:* " + IntegerToString(ticket) + "\n";
    telegramMessage += "─────────────────────────";
    
    if(EnableDiscordAlerts) SendDiscordMessage(discordMessage);
    if(EnableTelegramAlerts) SendTelegramMessage(telegramMessage);
}

//+------------------------------------------------------------------+
//| Send trade close alert                                           |
//+------------------------------------------------------------------+
void SendTradeCloseAlert(ulong dealTicket)
{
    string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
    double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
    double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
    double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
    ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
    datetime closeTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    string reasonStr = "";
    string reasonEmoji = "";
    
    if(reason == DEAL_REASON_SL)
    {
        reasonStr = " (Stop Loss Hit)";
       
    }
    else if(reason == DEAL_REASON_TP)
    {
        reasonStr = " (Take Profit Hit)";
        
    }
   
    
    
    string profitText = (profit >= 0) ? "Profit: $+" : "Loss: $-";
    
    // Discord message
    string discordMessage =" **TRADE CLOSED**" + reasonStr + "\n";
    discordMessage += "**Symbol:** " + symbol + "\n";
    discordMessage += "**Volume:** " + DoubleToString(volume, 2) + "\n";
    discordMessage += "**Close Price:** " + DoubleToString(price, digits) + "\n";
    discordMessage +=" **" + profitText + DoubleToString(MathAbs(profit), 2) + "**\n";
    discordMessage += "**Time:** " + TimeToString(closeTime, TIME_SECONDS) + "\n";
    discordMessage += "**Deal:** " + IntegerToString(dealTicket) + "\n";
    discordMessage +=" **Status:** " + ((profit >= 0) ? "PROFITABLE" : "LOSS") + "\n";
    discordMessage += "-----------------------------";
    
    // Telegram message
    string telegramMessage =" *TRADE CLOSED*" + reasonStr + "\n\n";
    telegramMessage += "*Symbol:* " + symbol + "\n";
    telegramMessage += "*Volume:* " + DoubleToString(volume, 2) + "\n";
    telegramMessage += "*Close Price:* " + DoubleToString(price, digits) + "\n";
    telegramMessage += " *" + profitText + DoubleToString(MathAbs(profit), 2) + "*\n";
    telegramMessage += "*Time:* " + TimeToString(closeTime, TIME_SECONDS) + "\n";
    telegramMessage += "*Deal:* " + IntegerToString(dealTicket) + "\n";
    telegramMessage += " *Status:* " + ((profit >= 0) ? "PROFITABLE" : "LOSS") + "\n";
    telegramMessage += "─────────────────────────";
    
    if(EnableDiscordAlerts) SendDiscordMessage(discordMessage);
    if(EnableTelegramAlerts) SendTelegramMessage(telegramMessage);
}

//+------------------------------------------------------------------+
//| Check for daily summary                                          |
//+------------------------------------------------------------------+
void CheckDailySummary()
{
    if(!EnableDailySummary) return;
    
    MqlDateTime currentTime, lastSummary;
    TimeToStruct(TimeCurrent(), currentTime);
    TimeToStruct(lastSummaryDate, lastSummary);
    
    // Parse summary time
    string timeParts[];
    StringSplit(SummaryTime, StringGetCharacter(":", 0), timeParts);
    int summaryHour = (int)StringToInteger(timeParts[0]);
    int summaryMinute = (int)StringToInteger(timeParts[1]);
    
    if(currentTime.day != lastSummary.day && 
       currentTime.hour >= summaryHour && 
       currentTime.min >= summaryMinute)
    {
        SendDailySummary();
        lastSummaryDate = TimeCurrent();
        dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    }
}

//+------------------------------------------------------------------+
//| Send daily summary                                               |
//+------------------------------------------------------------------+
void SendDailySummary()
{
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dailyPL = currentBalance - dayStartBalance;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    
    // Get daily statistics from history
    datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    HistorySelect(dayStart, TimeCurrent());
    
    int totalTrades = 0;
    int winningTrades = 0;
    int losingTrades = 0;
    double totalProfit = 0;
    double bestTrade = 0;
    double worstTrade = 0;
    
    int deals = HistoryDealsTotal();
    for(int i = 0; i < deals; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket > 0)
        {
            ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(dealEntry == DEAL_ENTRY_OUT)
            {
                double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                totalProfit += profit;
                totalTrades++;
                
                if(profit > 0) winningTrades++;
                else if(profit < 0) losingTrades++;
                
                if(profit > bestTrade) bestTrade = profit;
                if(profit < worstTrade) worstTrade = profit;
            }
        }
    }
    
  
    
    // Discord message
    string discordMessage = "**DAILY TRADING SUMMARY**\n";
    discordMessage += "**Date:** " + TimeToString(TimeCurrent(), TIME_DATE) + "\n\n";
    discordMessage += "**Performance Overview:**\n";
    discordMessage += " Daily P/L: $" + DoubleToString(dailyPL, 2) + "\n";
    discordMessage += "Balance: $" + DoubleToString(currentBalance, 2) + "\n";
    discordMessage += "Equity: $" + DoubleToString(equity, 2) + "\n";
    discordMessage += "Free Margin: $" + DoubleToString(freeMargin, 2) + "\n";
    if(marginLevel > 0) discordMessage += "📊 Margin Level: " + DoubleToString(marginLevel, 2) + "%\n";
    discordMessage += "\n**Trading Statistics:**\n";
    discordMessage += "Total Trades: " + IntegerToString(totalTrades) + "\n";
    discordMessage += "Winning Trades: " + IntegerToString(winningTrades) + "\n";
    discordMessage += "Losing Trades: " + IntegerToString(losingTrades) + "\n";
    
    if(totalTrades > 0)
    {
        double winRate = (double)winningTrades / totalTrades * 100;
        discordMessage += "Win Rate: " + DoubleToString(winRate, 1) + "%\n";
        discordMessage += "Best Trade: $" + DoubleToString(bestTrade, 2) + "\n";
        discordMessage += "Worst Trade: $" + DoubleToString(worstTrade, 2) + "\n";
    }
    
    discordMessage += "\n**Current Status:**\n";
    discordMessage += "Active Positions: " + IntegerToString(PositionsTotal()) + "\n";
    discordMessage += "Messages Sent: " + IntegerToString(messageCount + telegramMessageCount) + "\n";
    discordMessage += "--------------------";
    
    // Telegram message
    string telegramMessage = "*DAILY TRADING SUMMARY*\n\n";
    telegramMessage += "*Date:* " + TimeToString(TimeCurrent(), TIME_DATE) + "\n\n";
    telegramMessage += "*Performance Overview:*\n";
    telegramMessage +=" *Daily P/L:* $" + DoubleToString(dailyPL, 2) + "\n";
    telegramMessage += "*Balance:* $" + DoubleToString(currentBalance, 2) + "\n";
    telegramMessage += "*Equity:* $" + DoubleToString(equity, 2) + "\n";
    telegramMessage += "*Free Margin:* $" + DoubleToString(freeMargin, 2) + "\n";
    if(marginLevel > 0) telegramMessage += "*Margin Level:* " + DoubleToString(marginLevel, 2) + "%\n";
    telegramMessage += "\n*Trading Statistics:*\n";
    telegramMessage += "*Total Trades:* " + IntegerToString(totalTrades) + "\n";
    telegramMessage += "*Winning Trades:* " + IntegerToString(winningTrades) + "\n";
    telegramMessage += "*Losing Trades:* " + IntegerToString(losingTrades) + "\n";
    
    if(totalTrades > 0)
    {
        double winRate = (double)winningTrades / totalTrades * 100;
        telegramMessage += "*Win Rate:* " + DoubleToString(winRate, 1) + "%\n";
        telegramMessage += "*Best Trade:* $" + DoubleToString(bestTrade, 2) + "\n";
        telegramMessage += "*Worst Trade:* $" + DoubleToString(worstTrade, 2) + "\n";
    }
    
    telegramMessage += "\n*Current Status:*\n";
    telegramMessage += "*Active Positions:* " + IntegerToString(PositionsTotal()) + "\n";
    telegramMessage += "*Messages Sent:* " + IntegerToString(messageCount + telegramMessageCount) + "\n";
    telegramMessage += "─────────────────────────";
    
    if(EnableDiscordAlerts) SendDiscordMessage(discordMessage);
    if(EnableTelegramAlerts) SendTelegramMessage(telegramMessage);
}

//+------------------------------------------------------------------+
//| Send notification to all enabled platforms                       |
//+------------------------------------------------------------------+
void SendCustomNotification(string message)
{
    if(EnableDiscordAlerts) SendDiscordMessage(message);
    if(EnableTelegramAlerts) SendTelegramMessage(message);
}

//+------------------------------------------------------------------+
//| Send message to Discord with retry logic                         |
//+------------------------------------------------------------------+
void SendDiscordMessage(string message)
{
    string headers = "Content-Type: application/json\r\n";
    headers += "User-Agent: MT5-Discord-Tracker/3.0\r\n";
    
    // Rate limiting check
    if(TimeCurrent() - lastMessageTime < 1) 
    {
        Sleep(1000); // Wait 1 second between messages
    }
    lastMessageTime = TimeCurrent();
    
    // Escape special characters for JSON
    string escapedMessage = EscapeJsonString(message);
    string escapedBotName = EscapeJsonString(BotName);
    
    // Create JSON payload
    string json = "{";
    json += "\"username\":\"" + escapedBotName + "\",";
    json += "\"content\":\"" + escapedMessage + "\"";
    json += "}";
    
    char data[];
    StringToCharArray(json, data, 0, StringLen(json));
    
    bool success = false;
    int attempts = 0;
    
    while(!success && attempts < MessageRetryAttempts)
    {
        attempts++;
        
        char result[];
        string resultHeaders;
        int timeout = 10000; // 10 second timeout
        
        int res = WebRequest("POST", DiscordWebhookURL, headers, timeout, data, result, resultHeaders);
        
        if(res == 200 || res == 204)
        {
            success = true;
            messageCount++;
            Print("Discord message sent successfully (attempt ", attempts, ")");
        }
        else if(res == -1)
        {
            int lastError = GetLastError();
            Print("Discord webhook error (attempt ", attempts, "): Code ", lastError);
            if(attempts < MessageRetryAttempts) Sleep(2000 * attempts); // Exponential backoff
        }
        else if(res == 429) // Rate limited
        {
            Print("Rate limited by Discord (attempt ", attempts, "), waiting...");
            Sleep(5000); // Wait 5 seconds for rate limit
        }
        else
        {
            Print("Discord HTTP error (attempt ", attempts, "): ", res);
            Print("Response: ", CharArrayToString(result));
            if(attempts < MessageRetryAttempts) Sleep(1000 * attempts);
        }
    }
    
    if(!success)
    {
        Print("Failed to send Discord message after ", MessageRetryAttempts, " attempts");
        Print("JSON payload length: ", StringLen(json));
    }
}

//+------------------------------------------------------------------+
//| Send message to Telegram with retry logic                        |
//+------------------------------------------------------------------+
void SendTelegramMessage(string message)
{
    if(TelegramBotToken == "" || TelegramChatID == "") return;
    
    string headers = "Content-Type: application/json\r\n";
    headers += "User-Agent: MT5-Telegram-Tracker/3.0\r\n";
    
    // Rate limiting check for Telegram (30 messages per second max)
    static datetime lastTelegramMessage = 0;
    if(TimeCurrent() - lastTelegramMessage < 1) 
    {
        Sleep(1100); // Wait 1.1 seconds between Telegram messages
    }
    lastTelegramMessage = TimeCurrent();
    
    // Escape special characters for Telegram markdown
    string escapedMessage = EscapeTelegramString(message);
    
    // Create Telegram API URL
    string telegramURL = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage";
    
    // Create JSON payload for Telegram
    string json = "{";
    json += "\"chat_id\":\"" + TelegramChatID + "\",";
    json += "\"text\":\"" + escapedMessage + "\",";
    json += "\"parse_mode\":\"Markdown\",";
    json += "\"disable_web_page_preview\":true";
    json += "}";
    
    char data[];
    StringToCharArray(json, data, 0, StringLen(json));
    
    bool success = false;
    int attempts = 0;
    
    while(!success && attempts < MessageRetryAttempts)
    {
        attempts++;
        
        char result[];
        string resultHeaders;
        int timeout = 15000; // 15 second timeout for Telegram
        
        int res = WebRequest("POST", telegramURL, headers, timeout, data, result, resultHeaders);
        
        if(res == 200)
        {
            success = true;
            telegramMessageCount++;
            Print("Telegram message sent successfully (attempt ", attempts, ")");
        }
        else if(res == -1)
        {
            int lastError = GetLastError();
            Print("Telegram API error (attempt ", attempts, "): Code ", lastError);
            if(attempts < MessageRetryAttempts) Sleep(2000 * attempts); // Exponential backoff
        }
        else if(res == 429) // Rate limited
        {
            Print("Rate limited by Telegram (attempt ", attempts, "), waiting...");
            Sleep(10000); // Wait 10 seconds for Telegram rate limit
        }
        else
        {
            Print("Telegram HTTP error (attempt ", attempts, "): ", res);
            string response = CharArrayToString(result);
            Print("Response: ", response);
            
            // Check for specific Telegram errors
            if(StringFind(response, "chat not found") >= 0)
            {
                Print("Telegram Chat ID not found or bot not added to chat");
                break; // Don't retry for invalid chat ID
            }
            else if(StringFind(response, "bot was blocked") >= 0)
            {
                Print("Bot was blocked by user");
                break; // Don't retry if blocked
            }
            
            if(attempts < MessageRetryAttempts) Sleep(1000 * attempts);
        }
    }
    
    if(!success)
    {
        Print("Failed to send Telegram message after ", MessageRetryAttempts, " attempts");
        Print("JSON payload length: ", StringLen(json));
    }
}

//+------------------------------------------------------------------+
//| Escape special characters for JSON                              |
//+------------------------------------------------------------------+
string EscapeJsonString(string inputStr)
{
    string output = inputStr;
    
    // Replace in specific order to avoid double-escaping
    StringReplace(output, "\\", "\\\\");
    StringReplace(output, "\"", "\\\"");
    StringReplace(output, "\n", "\\n");
    StringReplace(output, "\r", "\\r");
    StringReplace(output, "\t", "\\t");
    StringReplace(output, CharToString(0x08), "\\b"); // Fix for backspace
    StringReplace(output, "\f", "\\f");
    
    return output;
}

//+------------------------------------------------------------------+
//| Escape special characters for Telegram Markdown                 |
//+------------------------------------------------------------------+
string EscapeTelegramString(string inputStr)
{
    string output = inputStr;
    
    // Escape special Telegram markdown characters
    StringReplace(output, "\\", "\\\\");
    StringReplace(output, "_", "\\_");
    StringReplace(output, "[", "\\[");
    StringReplace(output, "]", "\\]");
    StringReplace(output, "(", "\\(");
    StringReplace(output, ")", "\\)");
    StringReplace(output, "~", "\\~");
    StringReplace(output, "`", "\\`");
    StringReplace(output, ">", "\\>");
    StringReplace(output, "#", "\\#");
    StringReplace(output, "+", "\\+");
    StringReplace(output, "-", "\\-");
    StringReplace(output, "=", "\\=");
    StringReplace(output, "|", "\\|");
    StringReplace(output, "{", "\\{");
    StringReplace(output, "}", "\\}");
    StringReplace(output, ".", "\\.");
    StringReplace(output, "!", "\\!");
    
    return output;
}

//+------------------------------------------------------------------+
//| Get uninitialization reason text                                 |
//+------------------------------------------------------------------+
string GetUninitReasonText(int reason)
{
    switch(reason)
    {
        case REASON_PROGRAM: return "EA stopped by user";
        case REASON_REMOVE: return "EA removed from chart";
        case REASON_RECOMPILE: return "EA recompiled";
        case REASON_CHARTCHANGE: return "Chart symbol/period changed";
        case REASON_CHARTCLOSE: return "Chart closed";
        case REASON_PARAMETERS: return "EA parameters changed";
        case REASON_ACCOUNT: return "Account changed";
        case REASON_TEMPLATE: return "Template changed";
        case REASON_INITFAILED: return "Initialization failed";
        case REASON_CLOSE: return "Terminal closed";
        default: return "Unknown reason (" + IntegerToString(reason) + ")";
    }
}
