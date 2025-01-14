terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

variable "cloud_id" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "tg_bot_key" {
  type = string
}

variable "iam_token" {
  type = string
}

provider "yandex" {
  cloud_id = var.cloud_id
  folder_id = var.folder_id
  service_account_key_file = "/Users/cumelch/keys/yc-key.json"
}

resource "yandex_iam_service_account" "telegram-bot" {
  name = "telegram-bot"
  folder_id = var.folder_id
}

resource "yandex_resourcemanager_folder_iam_binding" "storage-bind" {
  folder_id = var.folder_id
  role = "storage.admin"

  members = [
    "serviceAccount:${yandex_iam_service_account.telegram-bot.id}",
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "vision-bind" {
  folder_id = var.folder_id
  role = "ai.vision.user"

  members = [
    "serviceAccount:${yandex_iam_service_account.telegram-bot.id}",
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "llm-bind" {
  folder_id = var.folder_id
  role = "ai.languageModels.user"

  members = [
    "serviceAccount:${yandex_iam_service_account.telegram-bot.id}",
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "func-admin-bind" {
  folder_id = var.folder_id
  role = "serverless.functions.admin"

  members = [
    "serviceAccount:${yandex_iam_service_account.telegram-bot.id}",
  ]
}

resource "yandex_storage_bucket" "instructions-bucket" {
  bucket = "telegram-bot-instructions"
  folder_id = var.folder_id
}

resource "yandex_storage_object" "instruction" {
  bucket = yandex_storage_bucket.instructions-bucket.id
  key = "instruction.txt"
  source = "instruction.txt"
}

resource "archive_file" "zip" {
  type = "zip"
  output_path = "tg_bot.zip"
  source_dir = "tg_bot"
}

resource "yandex_function" "func" {
  name = "telegram-bot"
  user_hash = archive_file.zip.output_sha256
  runtime = "python312"
  entrypoint = "controllers.handler"
  memory = 128
  execution_timeout = 300
  service_account_id = yandex_iam_service_account.telegram-bot.id

  environment = {
    "tg_bot_key" = var.tg_bot_key
    "iam_token" = var.iam_token
    "folder_id" = var.folder_id
    "cloud_id" = var.cloud_id
    "instructions_path" = "https://${yandex_storage_bucket.instructions-bucket.bucket}.storage.yandexcloud.net/${yandex_storage_object.instruction.key}"
  }

  content {
    zip_filename = archive_file.zip.output_path
  }
}

resource "yandex_function_iam_binding" "func-invoker-bind" {
  function_id = yandex_function.func.id
  role = "serverless.functions.invoker"

  members = [
    "system:allUsers",
  ]
}

resource "null_resource" "curl" {
  provisioner "local-exec" {
    command = "curl --insecure -X POST https://api.telegram.org/bot${var.tg_bot_key}/setWebhook?url=https://functions.yandexcloud.net/${yandex_function.func.id}"
  }

  triggers = {
    tg_bot_key = var.tg_bot_key
  }

  provisioner "local-exec" {
    when = destroy
    command = "curl --insecure -X POST https://api.telegram.org/bot${self.triggers.tg_bot_key}/deleteWebhook"
  }
}
