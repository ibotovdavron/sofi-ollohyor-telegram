
import os
import asyncio
import logging

from aiogram import Bot, Dispatcher
from aiogram.filters import CommandStart
from aiogram.types import (
    Message,
    InlineKeyboardMarkup,
    InlineKeyboardButton,
    WebAppInfo,
)

logging.basicConfig(level=logging.INFO)

TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
WEBAPP_URL = os.getenv("WEBAPP_URL", "")

dp = Dispatcher()


@dp.message(CommandStart())
async def start(message: Message):
    text = (
        f"Assalomu alaykum, {message.from_user.full_name}!\n\n"
        "So‘fi Ollohyor o‘quv markaziga xush kelibsiz!"
    )

    keyboard = None

    if WEBAPP_URL.startswith("https://"):
        keyboard = InlineKeyboardMarkup(
            inline_keyboard=[[
                InlineKeyboardButton(
                    text="📱 Ilovani ochish",
                    web_app=WebAppInfo(url=WEBAPP_URL),
                )
            ]]
        )
    else:
        text += "\n\nIlova hozir sozlanmoqda."

    await message.answer(text, reply_markup=keyboard)


async def main():
    if not TOKEN:
        raise RuntimeError(
            "TELEGRAM_BOT_TOKEN sozlanmagan!"
        )

    bot = Bot(token=TOKEN)

    try:
        await dp.start_polling(bot)
    finally:
        await bot.session.close()


if __name__ == "__main__":
    asyncio.run(main())
  
