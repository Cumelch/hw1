import os
import requests
import json
import telebot
import base64
from yandex_gpt import YandexGPT, YandexGPTConfigManagerForIAMToken

config = YandexGPTConfigManagerForIAMToken(model_type="yandexgpt-lite", catalog_id=os.getenv("folder_id"), iam_token=os.getenv("iam_token"))
yandex_gpt = YandexGPT(config_manager=config)
bot = telebot.TeleBot(os.getenv("tg_bot_key"))

def get_completion(message):
    response = requests.get(os.getenv("instructions_path"))
    instructions = response.text
    messages = [{"role": "system", "text": instructions}, {"role": "user", "text": message}]
    completion = yandex_gpt.get_sync_completion(messages=messages)
    return completion

def get_text(photo_data):
    response = requests.post(
        "https://ocr.api.cloud.yandex.net/ocr/v1/recognizeText", 
        json={
            "mimeType": "JPEG",
            "languageCodes": ["*"],
            "model": "page",
            "content": photo_data,
        },
        headers={
            "Content-Type": "application/json", 
            "Authorization": "Bearer {}".format(os.getenv("iam_token")),
            "x-folder-id": os.getenv("folder_id"),
            "x-data-logging-enabled": "true"
        }
    )
    return "Ответь на вопросы этого билета:\n\n" + response.json()["result"]["textAnnotation"]["fullText"]

@bot.message_handler(commands=['start', 'help'])
def answer_start_help(message):
    bot.reply_to(message, "Я помогу подготовить ответ на экзаменационный вопрос по дисциплине \"Операционные системы\". Пришлите мне фотографию с вопросом или наберите его текстом.")

@bot.message_handler(content_types=["text"])
def answer_text(message):
    try:
        bot.reply_to(message, get_completion(message.text))
    except:
        bot.reply_to(message, "Я не смог подготовить ответ на экзаменационный вопрос.")

@bot.message_handler(content_types=["photo"])
def answer_photo(message):
    if message.media_group_id:
        bot.reply_to(message, "Я могу обработать только одну фотографию.")
        return

    photo = message.photo[-1]
    file_info = bot.get_file(photo.file_id)
    file_bytes = bot.download_file(file_info.file_path)
    photo_data = base64.b64encode(file_bytes).decode("utf-8")

    try:
        text = get_text(photo_data)
    except:
        bot.reply_to(message, "Я не могу обработать эту фотографию.")

    if text:
        try:
            bot.reply_to(message, get_completion(text))
        except:
            bot.reply_to(message, "Я не смог подготовить ответ на экзаменационный вопрос.")
    else:
        bot.reply_to(message, "Я не могу обработать эту фотографию.")

@bot.message_handler(func=lambda message: True, content_types=['audio','voice','video','document','location','contact','sticker'])
def answer_other(message):
    bot.reply_to(message, "Я могу обработать только текстовое сообщение или фотографию.")

def handler(event, context):
    if event.get('httpMethod') == 'POST':
        body = event.get('body')

        try:
            update_data = json.loads(body)
            update = telebot.types.Update.de_json(update_data)
            bot.process_new_updates([update])
            return {"statusCode": 200, "body": "OK"}
        except:
            return {"statusCode": 500, 'body': "Internal server error"}