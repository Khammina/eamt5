//+------------------------------------------------------------------+
//|                                        TradeToDiscord.mq5        |
//|         Real-time trade open alerts to Discord for MT5           |
//+------------------------------------------------------------------+
#property strict

input string webhook_url = "https://discord.com/api/webhooks/1376145767508742214/SJZRCrSYjoOXQyHLYTrS4NkuDc8jbS5fKxBvhn2lrCgt3NU_ddiABkR7UplEfvodysXw";

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("✅ TradeToDiscord EA initialized. Waiting for trade events...");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("🛑 TradeToDiscord EA stopped.");
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      string tradeType = (trans.deal_type == DEAL_TYPE_BUY) ? "Buy" :
                         (trans.deal_type == DEAL_TYPE_SELL) ? "Sell" : "Deal";

      // Simplified message with newlines for Discord formatting
      string msg = tradeType + " Trade Opened\\n"
                 + "Symbol: " + trans.symbol + "\\n"
                 + "Lot: " + DoubleToString(trans.volume, 2) + "\\n"
                 + "Price: " + DoubleToString(trans.price, 2) + "\\n"
                 + "Time: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);

      SendDiscordMessage(msg);
   }
}

//+------------------------------------------------------------------+
//| Send message to Discord with robust JSON escaping                |
//+------------------------------------------------------------------+
void SendDiscordMessage(string message)
{
   // Comprehensive escaping of special characters for JSON
   string escaped_message = message;
   StringReplace(escaped_message, "\\", "\\\\");   // Escape backslashes
   StringReplace(escaped_message, "\"", "\\\"");   // Escape double quotes
   StringReplace(escaped_message, "\r", "\\r");    // Escape carriage returns
   StringReplace(escaped_message, "\t", "\\t");    // Escape tabs
   StringReplace(escaped_message, "\x08", "\\b");  // Escape backspaces
   StringReplace(escaped_message, "\f", "\\f");    // Escape form feeds
   StringReplace(escaped_message, "/", "\\/");     // Escape forward slashes

   // Construct JSON payload
   string payload = "{\"content\": \"" + escaped_message + "\"}";
   
   // Validate JSON payload (basic check)
   if (StringFind(payload, "{") == -1 || StringFind(payload, "}") == -1 || 
       StringFind(payload, "\"content\":") == -1)
   {
      Print("❌ Invalid JSON payload: ", payload);
      return;
   }

   // Convert to UTF-8 char array, excluding null terminator
   uchar post[];
   int len = StringToCharArray(payload, post, 0, StringLen(payload), CP_UTF8);
   if (len <= 0)
   {
      Print("❌ Failed to convert payload to char array");
      return;
   }

   // Debug: Print the payload and raw post array
   Print("📤 Sending payload: ", payload);
   string post_str = "";
   for (int i = 0; i < len; i++)
      post_str += StringFormat("%02X ", post[i]);
   Print("📤 Raw post data (hex): ", post_str);

   // Send WebRequest
   uchar result[];
   string headers = "Content-Type: application/json\r\n";
   string response_headers;

   int timeout = 5000;
   int res = WebRequest("POST", webhook_url, headers, timeout, post, result, response_headers);

   if (res == -1)
   {
      Print("❌ WebRequest failed. Error code: ", GetLastError());
      Print("Response headers: ", response_headers);
   }
   else
   {
      string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      Print("✅ Discord response: ", response, " | HTTP Status: ", res, " | Response headers: ", response_headers);
   }
}
