import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  final h = context.request.headers;
  return Response.json(body: {
    'cf': h['cf-connecting-ip'],
    'true': h['true-client-ip'],
    'xff': h['x-forwarded-for'],
  });
}
