import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dioxide/dioxide.dart' as dioxide;
import 'package:source_gen/source_gen.dart';

import 'base.dart';

void generateExtra(MethodElement m, List<Code> blocks, String localExtraVar) {
  final extras = <String, dynamic>{};
  _getExtrasAnnotation(m).forEach((extra) {
    extras.addAll((extra.peek('data')?.mapValue ?? {}).map((k, v) => MapEntry(
              k?.toStringValue() ??
                  (throw InvalidGenerationSourceError(
                    'Invalid key for extra Map, only `String` keys are supported',
                    element: m,
                    todo: 'Make sure all keys are of string type',
                  )),
              v?.toBoolValue() ??
                  v?.toDoubleValue() ??
                  v?.toIntValue() ??
                  v?.toStringValue() ??
                  v?.toListValue() ??
                  v?.toMapValue() ??
                  v?.toSetValue() ??
                  v?.toSymbolValue() ??
                  (v?.toTypeValue() ?? (v != null ? Code(revivedLiteral(v)) : Code('null'))),
            )) ??
        {});
  });

  final extraInParam = getAnnotations(m, dioxide.Extra);
  extras.addAll(extraInParam.map((k, v) {
    final value = v.peek('value')?.stringValue ?? k.displayName;
    return MapEntry(value, refer(k.displayName));
  }));

  blocks.add(literalMap(
    extras,
    refer('String'),
    refer('dynamic'),
  ).assignConst(localExtraVar).statement);
}

Iterable<ConstantReader> _getExtrasAnnotation(MethodElement method) {
  final annotations = typeChecker(dioxide.Extras).annotationsOf(method, throwOnUnresolved: false);
  return annotations.map((extra) => ConstantReader(extra));
}

/// Returns `$revived($args $kwargs)`, this won't have ending semi-colon (`;`).
/// [object] must not be null.
/// [object] is assumed to be a constant.
String revivedLiteral(
  Object object, {
  DartEmitter? dartEmitter,
}) {
  dartEmitter ??= DartEmitter();

  ArgumentError.checkNotNull(object, 'object');

  Revivable? revived;
  if (object is Revivable) {
    revived = object;
  }
  if (object is DartObject) {
    revived = ConstantReader(object).revive();
  }
  if (object is ConstantReader) {
    revived = object.revive();
  }
  if (revived == null) {
    throw ArgumentError.value(
        object, 'object', 'Only `Revivable`, `DartObject`, `ConstantReader` are supported values');
  }

  String instantiation = '';
  final location = revived.source.toString().split('#');

  /// If this is a class instantiation then `location[1]` will be populated
  /// with the class name
  if (location.length > 1) {
    instantiation = location[1] + (revived.accessor.isNotEmpty ? '.${revived.accessor}' : '');
  } else {
    /// Getters, Setters, Methods can't be declared as constants so this
    /// literal must either be a top-level constant or a static constant and
    /// can be directly accessed by `revived.accessor`
    return revived.accessor;
  }

  final args = StringBuffer();
  final kwargs = StringBuffer();
  Spec objectToSpec(DartObject? object) {
    if (object == null) return literalNull;
    final constant = ConstantReader(object);
    if (constant.isNull) {
      return literalNull;
    }

    if (constant.isBool) {
      return literal(constant.boolValue);
    }

    if (constant.isDouble) {
      return literal(constant.doubleValue);
    }

    if (constant.isInt) {
      return literal(constant.intValue);
    }

    if (constant.isString) {
      return literal(constant.stringValue);
    }

    if (constant.isList) {
      return literalList(constant.listValue.map(objectToSpec));
      // return literal(constant.listValue);
    }

    if (constant.isMap) {
      return literalMap(
          Map.fromIterables(constant.mapValue.keys.map(objectToSpec), constant.mapValue.values.map(objectToSpec)));
      // return literal(constant.mapValue);
    }

    if (constant.isSymbol) {
      return Code('Symbol(${constant.symbolValue})');
      // return literal(constant.symbolValue);
    }

    if (constant.isNull) {
      return literalNull;
    }

    if (constant.isType) {
      return refer(displayString(constant.typeValue));
    }

    if (constant.isLiteral) {
      return literal(constant.literalValue);
    }

    /// Perhaps an object instantiation?
    /// In that case, try initializing it and remove `const` to reduce noise
    final revived = revivedLiteral(constant.revive(), dartEmitter: dartEmitter).replaceFirst('const ', '');
    return Code(revived);
  }

  for (var arg in revived.positionalArguments) {
    final literalValue = objectToSpec(arg);

    args.write('${literalValue.accept(dartEmitter)},');
  }

  for (var arg in revived.namedArguments.keys) {
    final literalValue = objectToSpec(revived.namedArguments[arg]!);

    kwargs.write('$arg:${literalValue.accept(dartEmitter)},');
  }

  return '$instantiation($args $kwargs)';
}
