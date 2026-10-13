<?php

namespace App\Services;

class MailReadiness
{
    public function configured(): bool
    {
        if (! config('food.email_enabled') || ! filter_var(config('mail.from.address'), FILTER_VALIDATE_EMAIL)) {
            return false;
        }
        if (app()->isProduction() && parse_url((string) config('app.url'), PHP_URL_SCHEME) !== 'https') {
            return false;
        }

        $mailer = config('mail.default');
        if ($mailer === 'smtp') {
            return filled(config('mail.mailers.smtp.host')) && filled(config('mail.mailers.smtp.port'));
        }

        return match ($mailer) {
            'ses' => filled(config('services.ses.key')) && filled(config('services.ses.secret')),
            'postmark' => filled(config('services.postmark.key')),
            'resend' => filled(config('services.resend.key')),
            'sendmail' => is_executable(strtok((string) config('mail.mailers.sendmail.path'), ' ')),
            default => false,
        };
    }

    public function requireConfigured(): void
    {
        abort_unless($this->configured(), 503, 'ระบบอีเมลยังไม่ได้ตั้งค่า กรุณาติดต่อผู้ดูแลก่อนสมัครหรือขอรีเซ็ตรหัสผ่าน');
    }
}
