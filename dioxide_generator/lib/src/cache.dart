import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dioxide/dioxide.dart' as dioxide;
import 'package:source_gen/source_gen.dart';

import 'base.dart';

Map<String, Expression> generateCache(MethodElement m) {
  final cache = _getCacheAnnotation(m);
  final result = <String, Expression>{};
  if (cache != null && cache.toString() != '') {
    final maxAge = cache.peek('maxAge')?.intValue;
    final maxStale = cache.peek('maxStale')?.intValue;
    final minFresh = cache.peek('minFresh')?.intValue;
    final noCache = cache.peek('noCache')?.boolValue;
    final noStore = cache.peek('noStore')?.boolValue;
    final noTransform = cache.peek('noTransform')?.boolValue;
    final onlyIfCached = cache.peek('onlyIfCached')?.boolValue;
    final other = (cache.peek('other')?.listValue ?? const []).map((e) => e.toStringValue());
    final otherResult = <String>[];

    for (var element in other) {
      if (element != null) {
        otherResult.add(element);
      }
    }

    final values = <String>[
      maxAge != null ? 'max-age=$maxAge' : '',
      maxStale != null ? 'max-stale=$maxStale' : '',
      minFresh != null ? 'max-fresh=$minFresh' : '',
      (noCache == true) ? 'no-cache' : '',
      (noStore == true) ? 'no-store' : '',
      (noTransform == true) ? 'no-transform' : '',
      (onlyIfCached == true) ? 'only-if-cached' : '',
      ...otherResult
    ];

    final value = values.where((element) => element != '').join(', ');

    result.putIfAbsent(HttpHeaders.cacheControlHeader, () => literal(value));
  }
  return result;
}

ConstantReader? _getCacheAnnotation(MethodElement method) {
  final annotation = typeChecker(dioxide.CacheControl).firstAnnotationOf(method, throwOnUnresolved: false);
  if (annotation != null) return ConstantReader(annotation);
  return null;
}
