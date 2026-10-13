<!doctype html>
<html lang="th">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="referrer" content="no-referrer">
    <title>ตั้งรหัสผ่านใหม่ · MSU Food</title>
    <style>body{margin:0;padding:32px 16px;background:#f6f7f8;color:#203139;font:16px/1.6 system-ui,sans-serif}main{max-width:420px;margin:36px auto;padding:28px;background:white;border-radius:20px}h1{font-size:25px}label{display:block;margin-top:16px}input,button{box-sizing:border-box;width:100%;font:inherit;padding:12px;border:1px solid #d5dce0;border-radius:10px}button{margin-top:24px;background:#f66a32;border:0;color:#192c34;font-weight:700}p{color:#50606b}.error{color:#b42318}.success{color:#067647}</style>
</head>
<body><main>
    <h1>ตั้งรหัสผ่านใหม่</h1>
    @if (session('status'))
        <p class="success" role="status">{{ session('status') }}</p>
    @else
        <p>ใช้รหัสผ่านอย่างน้อย 8 ตัวอักษร</p>
        @if ($errors->any())
            <p class="error" role="alert">{{ $errors->first() }}</p>
        @endif
        <form method="post" action="{{ route('password.update') }}">
            @csrf
            <input type="hidden" name="token" value="{{ $token }}">
            <label for="email">อีเมล</label>
            <input id="email" name="email" type="email" autocomplete="email" value="{{ old('email', $email) }}" required maxlength="255">
            <label for="password">รหัสผ่านใหม่</label>
            <input id="password" name="password" type="password" autocomplete="new-password" required minlength="8" maxlength="128">
            <label for="password_confirmation">ยืนยันรหัสผ่านใหม่</label>
            <input id="password_confirmation" name="password_confirmation" type="password" autocomplete="new-password" required minlength="8" maxlength="128">
            <button type="submit">บันทึกรหัสผ่านใหม่</button>
        </form>
    @endif
</main></body>
</html>
