fx_version 'cerulean'
games { 'gta5' }

author 'Azure(TheStoicBear)'
description 'AI Vehicle Job: fetch vehicle, dismantle for cash, police alerts on fail'
version '1.0.0'

shared_script 'config.lua'

client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'
files {
  'html/index.html',
  'html/js/main.js',
  'html/css/style.css',
  'html/img/*'
}
