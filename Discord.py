import MetaTrader5 as mt5
import time
import discord
from discord.ext import commands, tasks
import asyncio
import threading
from datetime import datetime

# Discord bot configuration
DISCORD_TOKEN = "MTM2ODk3NzIwNTc4NjU3NTAxMQ.Gsn1HV.bKxQxAGO7q1DP7wehLoMzDj3-4VoPq35GiGfSE"  # Replace with your token
CHANNEL_ID = "1368978046857515182"  # Replace with your channel ID

class MT5OrderTracker:
    def __init__(self):
        self.connected = False
        self.orders = {}  # {symbol: {order_id: order}}
        self.positions = {}  # {symbol: {position_id: position}}
        self.discord_bot = None
        self.bot_thread = None
        self.symbols = []  # List of all symbols to track

    def connect(self):
        """Connect to MT5 terminal and retrieve all symbols."""
        if not mt5.initialize():
            print(f"MT5 initialize() failed, error code = {mt5.last_error()}")
            return False

        self.connected = True
        print(f"Connected to MT5: {mt5.terminal_info()}")

        # Retrieve all symbols
        symbols = mt5.symbols_get()
        if not symbols:
            print("Failed to retrieve symbols")
            self.connected = False
            return False

        self.symbols = [symbol.name for symbol in symbols]
        print(f"Tracking {len(self.symbols)} symbols")
        return True

    def start_discord_bot(self):
        """Start Discord bot in a separate thread."""
        self.bot_thread = threading.Thread(target=self._run_discord_bot)
        self.bot_thread.daemon = True
        self.bot_thread.start()

    def _run_discord_bot(self):
        """Run the Discord bot."""
        intents = discord.Intents.default()
        intents.message_content = False  # Disable privileged intent
        bot = commands.Bot(command_prefix='!', intents=intents)
        self.discord_bot = bot

        @bot.event
        async def on_ready():
            print(f'Discord bot logged in as {bot.user}')
            track_orders.start()

        @tasks.loop(seconds=5)
        async def track_orders():
            await self.check_orders_and_positions()

        bot.run(DISCORD_TOKEN)

    async def send_discord_message(self, message):
        """Send message to Discord channel."""
        if not self.discord_bot:
            print("Discord bot not initialized")
            return

        try:
            channel = self.discord_bot.get_channel(int(CHANNEL_ID))
            if channel:
                await channel.send(message[:2000])  # Discord message length limit
            else:
                print(f"Could not find channel with ID {CHANNEL_ID}")
        except Exception as e:
            print(f"Error sending Discord message: {e}")

    async def check_orders_and_positions(self):
        """Check for new/closed orders and positions across all symbols."""
        if not self.connected:
            return

        # Track orders
        current_orders = {symbol: {} for symbol in self.symbols}
        orders = mt5.orders_get()
        if orders:
            for order in orders:
                if order.symbol not in current_orders:
                    continue
                order_id = order.ticket
                current_orders[order.symbol][order_id] = order

                # New order detected
                if order.symbol not in self.orders or order_id not in self.orders.get(order.symbol, {}):
                    await self.send_discord_message(
                        f"🔔 **New Order Placed**\n"
                        f"Symbol: {order.symbol}\n"
                        f"Type: {'Buy' if order.type == mt5.ORDER_TYPE_BUY else 'Sell'}\n"
                        f"Volume: {order.volume}\n"
                        f"Price: {order.price_open}\n"
                        f"Time: {datetime.fromtimestamp(order.time_setup)}"
                    )

        # Check for closed orders
        for symbol in self.orders:
            for order_id in self.orders[symbol]:
                if symbol not in current_orders or order_id not in current_orders[symbol]:
                    await self.send_discord_message(
                        f"🔔 **Order Closed/Executed**\n"
                        f"Symbol: {symbol}\n"
                        f"Order ID: {order_id}"
                    )

        self.orders = current_orders

        # Track positions
        current_positions = {symbol: {} for symbol in self.symbols}
        positions = mt5.positions_get()
        if positions:
            for position in positions:
                if position.symbol not in current_positions:
                    continue
                position_id = position.ticket
                current_positions[position.symbol][position_id] = position

                # New or updated position
                if position.symbol not in self.positions or position_id not in self.positions.get(position.symbol, {}):
                    await self.send_discord_message(
                        f"🔔 **New Position Opened**\n"
                        f"Symbol: {position.symbol}\n"
                        f"Type: {'Buy' if position.type == mt5.POSITION_TYPE_BUY else 'Sell'}\n"
                        f"Volume: {position.volume}\n"
                        f"Open Price: {position.price_open}\n"
                        f"SL: {position.sl}\n"
                        f"TP: {position.tp}\n"
                        f"Time: {datetime.fromtimestamp(position.time)}"
                    )
                else:
                    # Check for SL/TP updates
                    old_position = self.positions[position.symbol][position_id]
                    if old_position.sl != position.sl or old_position.tp != position.tp:
                        await self.send_discord_message(
                            f"🔄 **Position Updated**\n"
                            f"Symbol: {position.symbol}\n"
                            f"Position ID: {position_id}\n"
                            f"New SL: {position.sl}\n"
                            f"New TP: {position.tp}\n"
                            f"Current Profit: {position.profit}"
                        )

        # Check for closed positions
        for symbol in self.positions:
            for position_id in self.positions[symbol]:
                if symbol not in current_positions or position_id not in current_positions[symbol]:
                    position = self.positions[symbol][position_id]
                    await self.send_discord_message(
                        f"🔔 **Position Closed**\n"
                        f"Symbol: {position.symbol}\n"
                        f"Position ID: {position_id}\n"
                        f"Type: {'Buy' if position.type == mt5.POSITION_TYPE_BUY else 'Sell'}\n"
                        f"Volume: {position.volume}"
                    )

        self.positions = current_positions

    def run(self):
        """Start tracking orders and positions."""
        if not self.connected and not self.connect():
            print("Failed to connect to MT5")
            return

        print("Starting order and position tracking for all symbols")
        self.start_discord_bot()

        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("Order tracking stopped by user")
        except Exception as e:
            print(f"Error in order tracking: {e}")
        finally:
            mt5.shutdown()
            print("MT5 connection closed")
            if self.discord_bot:
                asyncio.run(self.discord_bot.close())
                print("Discord bot closed")

if __name__ == "__main__":
    tracker = MT5OrderTracker()
    tracker.run()