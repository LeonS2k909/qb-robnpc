fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qb-npcrobbery'
author 'Leon'
description 'Aim a gun to make NPCs surrender, then rob via qb-target.'
version '1.0.0'

dependencies {
    'qb-core',
    'qb-target'
}

shared_scripts {
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}
