import 'dart:io';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dotenv/dotenv.dart';

/// Chạy một lần khi khởi động: đọc .env, kiểm tra cấu hình, kết nối Firebase Admin và mail.
Future<void> init(InternetAddress ip, int port) async {
  final fileEnv = DotEnv(quiet: true);
  if (File('.env').existsSync()) fileEnv.load(['.env']);
  // Biến môi trường của hệ thống (Cloud Run, Docker) ưu tiên hơn file .env.
  final env = <String, String>{
    for (final key in AppConfig.knownKeys)
      if ((Platform.environment[key] ?? fileEnv[key]) case final String value) key: value,
  };

  final AppConfig config;
  try {
    config = AppConfig.fromEnvironment(env, defaultBuildings: AppConfig.loadDefaultBuildings());
  } on ConfigException catch (e) {
    stderr.writeln(e);
    stderr.writeln('Sao chép backend/.env.example thành backend/.env và điền đủ các giá trị trên.');
    exit(78); // EX_CONFIG
  }

  final services = AppServices.production(config);
  AppServices.instance = services;
  services.walks.startOverdueTimer();
  stdout.writeln('[campus_safety] OTP gửi qua email ${config.smtpUsername} (${config.smtpHost}:${config.smtpPort}).');
}

Future<HttpServer> run(Handler handler, InternetAddress ip, int port) {
  return serve(handler, ip, port);
}
