<?php

return [
    'whatsapp' => [
        'base_url' => env('WHATSAPP_SERVER'),
        'secret_key' => env('WHATSAPP_SECRET_KEY', ''),
        'token' => env('WHATSAPP_TOKEN'),
        'session' => env('WHATSAPP_SESSION', 'default'),
    ],
];
