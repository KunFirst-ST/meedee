<?php

return [
    'email_enabled' => (bool) env('AUTH_EMAIL_ENABLED', false),
    'callback_uris' => array_values(array_filter(array_map('trim', explode(',', (string) env('AUTH_CALLBACK_URIS', 'msufood://auth/callback,http://localhost:5173/auth/callback'))))),
    'cors_origins' => array_values(array_filter(array_map('trim', explode(',', (string) env('CORS_ALLOWED_ORIGINS', 'http://localhost:5173'))))),
    'token_lifetime_days' => 30,
];
