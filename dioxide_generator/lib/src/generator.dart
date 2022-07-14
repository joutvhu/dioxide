import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:built_collection/built_collection.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:dio/dio.dart';
import 'package:dioxide/dioxide.dart' as dioxide;
import 'package:source_gen/source_gen.dart';

import 'base.dart';
import 'base_url.dart';
import 'content_type.dart';
import 'extra.dart';
import 'header.dart';
import 'method.dart';
import 'response.dart';
import 'timeout.dart';

const _analyzerIgnores = '// ignore_for_file: unnecessary_brace_in_string_interps';

class DioxideGenerator extends GeneratorForAnnotation<dioxide.RestApi> {
  static const _queryParamsVar = 'queryParameters';
  static const _localHeadersVar = '_headers';
  static const _headersVar = 'headers';
  static const _dataVar = 'data';
  static const _localDataVar = '_data';
  static const _tempDataVar = '_tempData';
  static const _dioVar = '_dio';
  static const _extraVar = 'extra';
  static const _localExtraVar = '_extra';
  static const _contentType = 'contentType';
  static const _resultVar = '_result';
  static const _cancelToken = 'cancelToken';
  static const _onSendProgress = 'onSendProgress';
  static const _onReceiveProgress = 'onReceiveProgress';
  static const _path = 'path';
  var hasCustomOptions = false;

  /// Global options sepcefied in the `build.yaml`
  final DioxideOptions globalOptions;

  DioxideGenerator(this.globalOptions);

  /// Annotation details for [RestApi]
  late dioxide.RestApi clientAnnotation;

  @override
  String generateForAnnotatedElement(Element element, ConstantReader annotation, BuildStep buildStep) {
    if (element is! ClassElement) {
      final name = element.displayName;
      throw InvalidGenerationSourceError(
        'Generator cannot target `$name`.',
        todo: 'Remove the [RestApi] annotation from `$name`.',
      );
    }
    return _implementClass(element, annotation);
  }

  String _implementClass(ClassElement element, ConstantReader? annotation) {
    final className = element.name;
    final serializerEnumString = (annotation?.peek('serializer')?.revive().accessor);
    final deserializerEnumString = (annotation?.peek('deserializer')?.revive().accessor);
    final serializerParser = dioxide.Parser.values.firstWhereOrNull((e) => e.toString() == serializerEnumString);
    final deserializerParser = dioxide.Parser.values.firstWhereOrNull((e) => e.toString() == deserializerEnumString);
    clientAnnotation = dioxide.RestApi(
      autoCastResponse: (annotation?.peek('autoCastResponse')?.boolValue),
      baseUrl: (annotation?.peek('baseUrl')?.stringValue ?? ''),
      serializer: (serializerParser ?? dioxide.Parser.MapSerializable),
      deserializer: (deserializerParser ?? dioxide.Parser.MapSerializable),
    );
    final annotClassConsts = element.constructors.where((c) => !c.isFactory && !c.isDefaultConstructor);
    final classBuilder = Class((c) {
      c
        ..name = '_$className'
        ..types.addAll(element.typeParameters.map((e) => refer(e.name)))
        ..fields.add(_buildDioFiled())
        ..fields.add(buildBaseUrlFiled())
        ..fields.addAll(buildTimeoutFields())
        ..constructors.addAll(
          annotClassConsts.map(
            (e) => _generateConstructor(element, superClassConst: e),
          ),
        )
        ..methods.addAll(parseMethods(element));
      if (annotClassConsts.isEmpty) {
        c.constructors.add(_generateConstructor(element));
        c.implements.add(refer(_generateTypeParameterizedName(element)));
      } else {
        c.extend = Reference(_generateTypeParameterizedName(element));
      }
      if (hasCustomOptions) {
        c.methods.add(_generateOptionsCastMethod());
      }
      c.methods.add(_generateTypeSetterMethod());
      if (clientAnnotation.serializer == dioxide.Parser.DartSingleMapper) {
        c.methods.add(_generateSerializeMethod());
      }
      if (clientAnnotation.deserializer == dioxide.Parser.DartSingleMapper) {
        c.methods.add(_generateDeserializeMethod());
      }
    });

    final emitter = DartEmitter();
    return DartFormatter().format([_analyzerIgnores, classBuilder.accept(emitter)].join('\n\n'));
  }

  Field _buildDioFiled() => Field((m) => m
    ..name = _dioVar
    ..type = refer('Dio')
    ..modifier = FieldModifier.final$);

  Constructor _generateConstructor(
    ClassElement element, {
    ConstructorElement? superClassConst,
  }) =>
      Constructor((c) {
        c.requiredParameters.add(Parameter((p) => p
          ..name = _dioVar
          ..toThis = true));
        c.optionalParameters.add(buildBaseUrlParameter());
        c.optionalParameters.addAll(buildTimeoutParameters());
        if (superClassConst != null) {
          var superConstName = 'super';
          if (superClassConst.name.isNotEmpty) {
            superConstName += '.${superClassConst.name}';
            c.name = superClassConst.name;
          }
          final constParams = superClassConst.parameters;
          constParams.forEach((element) {
            if (!element.isOptional || element.isPrivate) {
              c.requiredParameters.add(Parameter((p) => p
                ..type = refer(displayString(element.type))
                ..name = element.name));
            } else {
              c.optionalParameters.add(Parameter((p) => p
                ..named = element.isNamed
                ..type = refer(displayString(element.type))
                ..name = element.name));
            }
          });
          final paramList = constParams.map((e) => (e.isNamed ? '${e.name}: ' : '') + '${e.name}');
          c.initializers.add(Code('$superConstName(' + paramList.join(',') + ')'));
        }
        final Iterable<Code> block = []
          ..addAll(buildBaseUrlDefaultValue(clientAnnotation))
          ..addAll(buildTimeoutDefaultValue(element));

        if (block.isNotEmpty) {
          c.body = Block.of(block);
        }
      });

  String _generateTypeParameterizedName(TypeParameterizedElement element) =>
      element.displayName + (element.typeParameters.isNotEmpty ? '<${element.typeParameters.join(',')}>' : '');

  Expression _generatePath(MethodElement m, ConstantReader method) {
    final paths = getAnnotations(m, dioxide.Path);
    String? definePath = method.peek('path')?.stringValue;
    paths.forEach((k, v) {
      final value = v.peek('value')?.stringValue ?? k.displayName;
      definePath = definePath?.replaceFirst(
          '{$value}', '\${${k.displayName}${k.type.element?.kind == ElementKind.ENUM ? '.name' : ''}}');
    });
    return literal(definePath);
  }

  Iterable<Method> parseMethods(ClassElement element) {
    return getMethodElements(element).map((m) => generateMethod(m, _generateRequest)!);
  }

  Code _generateRequest(MethodElement m, ConstantReader httpMethod) {
    final returnAsyncWrapper = m.returnType.isDartAsyncFuture ? 'return' : 'yield';
    final path = _generatePath(m, httpMethod);
    final blocks = <Code>[];

    generateExtra(m, blocks, _localExtraVar);

    _generateQueries(m, blocks, _queryParamsVar);
    Map<String, Expression> headers = generateHeaders(m);
    blocks.add(
        literalMap(headers.map((k, v) => MapEntry(literalString(k, raw: true), v)), refer('String'), refer('dynamic'))
            .assignFinal(_localHeadersVar)
            .statement);

    if (headers.isNotEmpty) {
      blocks.add(Code('${_localHeadersVar}.removeWhere((k, v) => v == null);'));
    }

    _generateRequestBody(blocks, _localDataVar, m);

    final extraOptions = {
      'method': literal(httpMethod.peek('method')?.stringValue),
      _headersVar: refer(_localHeadersVar),
      _extraVar: refer(_localExtraVar),
    };

    final contentTypeInHeader =
        headers.entries.firstWhereOrNull((i) => 'Content-Type'.toLowerCase() == i.key.toLowerCase())?.value;
    if (contentTypeInHeader != null) {
      extraOptions[_contentType] = contentTypeInHeader;
    }

    final contentType = getContentTypeAnnotation(m);
    if (contentType != null) {
      extraOptions[_contentType] = literal(contentType.peek('mime')?.stringValue);
    }

    extraOptions.addAll(buildBaseUrlOptions());

    final responseType = getResponseTypeAnnotation(m);
    if (responseType != null) {
      final v = responseType.peek('responseType')?.objectValue;
      log.info('ResponseType  :  ${v?.getField('index')?.toIntValue()}');
      final rsType = ResponseType.values.firstWhere((it) {
        return responseType.peek('responseType')?.objectValue.getField('index')?.toIntValue() == it.index;
      }, orElse: () {
        log.warning('responseType cast error!!!!');
        return ResponseType.json;
      });

      extraOptions['responseType'] = refer(rsType.toString());
    }
    final namedArguments = <String, Expression>{};
    namedArguments[_queryParamsVar] = refer(_queryParamsVar);
    namedArguments[_path] = path;
    namedArguments[_dataVar] = refer(_localDataVar);

    final cancelToken = getAnnotation(m, dioxide.CancelRequest);
    if (cancelToken != null) namedArguments[_cancelToken] = refer(cancelToken.item1.displayName);

    final sendProgress = getAnnotation(m, dioxide.SendProgress);
    if (sendProgress != null) namedArguments[_onSendProgress] = refer(sendProgress.item1.displayName);

    final receiveProgress = getAnnotation(m, dioxide.ReceiveProgress);
    if (receiveProgress != null) namedArguments[_onReceiveProgress] = refer(receiveProgress.item1.displayName);

    final wrapperedReturnType = getResponseType(m.returnType);
    final autoCastResponse = (globalOptions.autoCastResponse ?? (clientAnnotation.autoCastResponse ?? true));

    final options = _parseOptions(m, namedArguments, blocks, extraOptions);

    /// If autoCastResponse is false, return the response as it is
    if (!autoCastResponse) {
      blocks.add(
        refer('$_dioVar.fetch').call([options]).returned.statement,
      );
      return Block.of(blocks);
    }

    if (wrapperedReturnType == null || 'void' == wrapperedReturnType.toString()) {
      blocks.add(
        refer('await $_dioVar.fetch').call([options], {}, [refer('void')]).statement,
      );
      blocks.add(Code('$returnAsyncWrapper null;'));
      return Block.of(blocks);
    }

    final bool isWrappered = typeChecker(dioxide.HttpResponse).isExactlyType(wrapperedReturnType);
    final returnType = isWrappered ? getResponseType(wrapperedReturnType) : wrapperedReturnType;
    if (returnType == null || 'void' == returnType.toString()) {
      if (isWrappered) {
        blocks.add(
          refer('final $_resultVar = await $_dioVar.fetch').call([options], {}, [refer('void')]).statement,
        );
        blocks.add(Code('''
      final httpResponse = HttpResponse(null, $_resultVar);
      $returnAsyncWrapper httpResponse;
      '''));
      } else {
        blocks.add(
          refer('await $_dioVar.fetch').call([options], {}, [refer('void')]).statement,
        );
        blocks.add(Code('$returnAsyncWrapper null;'));
      }
    } else {
      final innerReturnType = getResponseInnerType(returnType);
      if (typeChecker(Response).isExactlyType(returnType)) {
        blocks.add(
          refer('await $_dioVar.fetch${innerReturnType != null ? '<${displayString(innerReturnType)}>' : ''}')
              .call([options])
              .assignFinal(_resultVar)
              .statement,
        );
        blocks.add(Code('final value = $_resultVar;'));
      } else if (typeChecker(List).isExactlyType(returnType) || typeChecker(BuiltList).isExactlyType(returnType)) {
        if (isBasicType(innerReturnType)) {
          blocks.add(
            refer('await $_dioVar.fetch<List<dynamic>>').call([options]).assignFinal(_resultVar).statement,
          );
          blocks.add(refer('$_resultVar.data')
              .propertyIf(thisNullable: returnType.isNullable, name: 'cast')
              .call([], {}, [refer('${displayString(innerReturnType)}')])
              .assignFinal('value')
              .statement);
        } else {
          blocks.add(
            refer('await $_dioVar.fetch<List<dynamic>>').call([options]).assignFinal(_resultVar).statement,
          );
          if (clientAnnotation.deserializer == dioxide.Parser.DartSingleMapper) {
            var param = refer('''<String,dynamic>{
              'resultType': '${displayString(innerReturnType)}',
              'data': $_resultVar.data!.cast<Map<String,dynamic>>()
            }''');
            if (clientAnnotation.compute) {
              blocks.add(refer('$_resultVar.data')
                  .conditionalIsNullIf(
                      thisNullable: returnType.isNullable,
                      whenFalse: refer('await compute').call([refer('_dioxideDeserialize'), param]))
                  .assignVar('value')
                  .statement);
            } else {
              blocks.add(refer('$_resultVar.data')
                  .conditionalIsNullIf(
                      thisNullable: returnType.isNullable, whenFalse: refer('await _dioxideDeserialize').call([param]))
                  .assignVar('value')
                  .statement);
            }
          } else {
            final Reference mapperCode;
            switch (clientAnnotation.deserializer) {
              case dioxide.Parser.MapSerializable:
                mapperCode =
                    refer('(dynamic i) => ${displayString(innerReturnType)}.fromMap(i as Map<String,dynamic>)');
                break;
              case dioxide.Parser.JsonSerializable:
                mapperCode =
                    refer('(dynamic i) => ${displayString(innerReturnType)}.fromJson(i as Map<String,dynamic>)');
                break;
              case dioxide.Parser.DartJsonMapper:
                mapperCode = refer(
                    '(dynamic i) => JsonMapper.fromMap<${displayString(innerReturnType)}>(i as Map<String,dynamic>)!');
                break;
              case dioxide.Parser.DartSingleMapper:
                throw Exception('Unreachable code');
            }
            blocks.add(
              refer('$_resultVar.data')
                  .propertyIf(thisNullable: returnType.isNullable, name: 'map')
                  .call([mapperCode])
                  .property('toList')
                  .call([])
                  .assignVar('value')
                  .statement,
            );
          }
        }
      } else if (typeChecker(Map).isExactlyType(returnType) || typeChecker(BuiltMap).isExactlyType(returnType)) {
        final types = getResponseInnerTypes(returnType)!;
        blocks.add(
          refer('await $_dioVar.fetch<Map<String,dynamic>>').call([options]).assignFinal(_resultVar).statement,
        );

        /// assume the first type is a basic type
        if (types.length > 1) {
          final firstType = types[0];
          final secondType = types[1];
          if (typeChecker(List).isExactlyType(secondType) || typeChecker(BuiltList).isExactlyType(secondType)) {
            final type = getResponseType(secondType);
            final Reference mapperCode;
            var future = false;
            switch (clientAnnotation.deserializer) {
              case dioxide.Parser.MapSerializable:
                mapperCode = refer('''
            (k, dynamic v) =>
                MapEntry(
                  k, (v as List)
                    .map((i) => ${displayString(type)}.fromMap(i as Map<String,dynamic>))
                    .toList()
                )
            ''');
                break;
              case dioxide.Parser.JsonSerializable:
                mapperCode = refer('''
            (k, dynamic v) =>
                MapEntry(
                  k, (v as List)
                    .map((i) => ${displayString(type)}.fromJson(i as Map<String,dynamic>))
                    .toList()
                )
            ''');
                break;
              case dioxide.Parser.DartJsonMapper:
                mapperCode = refer('''
            (k, dynamic v) =>
                MapEntry(
                  k, (v as List)
                    .map((i) => JsonMapper.fromMap<${displayString(type)}>(i as Map<String,dynamic>)!)
                    .toList()
                )
            ''');
                break;
              case dioxide.Parser.DartSingleMapper:
                log.warning('''
Return types should not be a map when running `Parser.DartSingleMapper`, as spawning an isolate per entry is extremely intensive.
You should create a new class to encapsulate the response.
''');
                future = true;
                mapperCode = refer('''
                (e) async => MapEntry(
                  e.key,
                  await ${clientAnnotation.compute ? 'compute(_dioxideDeserialize,' : '_dioxideDeserialize('}
                    <String,dynamic>{
                      'resultType': '${displayString(innerReturnType)}',
                      'data': (e.value as List).cast<Map<String,dynamic>>()
                    }))''');
                break;
            }
            if (future) {
              blocks.add(refer('Map.fromEntries')
                  .call([
                    refer('await Future.wait').call([
                      refer('$_resultVar.data!.entries.map').call([mapperCode])
                    ])
                  ])
                  .assignVar('value')
                  .statement);
            } else {
              blocks.add(refer('$_resultVar.data')
                  .propertyIf(thisNullable: returnType.isNullable, name: 'map')
                  .call([mapperCode])
                  .assignVar('value')
                  .statement);
            }
          } else if (!isBasicType(secondType)) {
            final Reference mapperCode;
            var future = false;
            switch (clientAnnotation.deserializer) {
              case dioxide.Parser.MapSerializable:
                mapperCode = refer(
                    '(k, dynamic v) => MapEntry(k, ${displayString(secondType)}.fromMap(v as Map<String,dynamic>))');
                break;
              case dioxide.Parser.JsonSerializable:
                mapperCode = refer(
                    '(k, dynamic v) => MapEntry(k, ${displayString(secondType)}.fromJson(v as Map<String,dynamic>))');
                break;
              case dioxide.Parser.DartJsonMapper:
                mapperCode = refer(
                    '(k, dynamic v) => MapEntry(k, JsonMapper.fromMap<${displayString(secondType)}>(v as Map<String,dynamic>)!)');
                break;
              case dioxide.Parser.DartSingleMapper:
                log.warning('''
Return types should not be a map when running `Parser.DartSingleMapper`, as spawning an isolate per entry is extremely intensive.
You should create a new class to encapsulate the response.
''');
                future = true;
                mapperCode = refer('''
                (e) async => MapEntry(
                  e.key, await ${clientAnnotation.compute ? 'compute(_dioxideDeserialize,' : '_dioxideDeserialize('}
                    <String,dynamic>{
                      'resultType': '${displayString(secondType)}',
                      'data': e.value as Map<String,dynamic>
                    }))''');
                break;
            }
            if (future) {
              blocks.add(refer('$_resultVar.data')
                  .conditionalIsNullIf(
                      thisNullable: returnType.isNullable,
                      whenFalse: refer('Map.fromEntries').call([
                        refer('await Future.wait').call([
                          refer('$_resultVar.data!.entries.map').call([mapperCode])
                        ])
                      ]))
                  .assignVar('value')
                  .statement);
            } else {
              blocks.add(refer('$_resultVar.data')
                  .propertyIf(thisNullable: returnType.isNullable, name: 'map')
                  .call([mapperCode])
                  .assignVar('value')
                  .statement);
            }
          } else {
            blocks.add(refer('$_resultVar.data')
                .propertyIf(thisNullable: returnType.isNullable, name: 'cast')
                .call([], {}, [
                  refer('${displayString(firstType)}'),
                  refer('${displayString(secondType)}'),
                ])
                .assignFinal('value')
                .statement);
          }
        } else {
          blocks.add(Code('final value = $_resultVar.data!;'));
        }
      } else {
        if (isBasicType(returnType)) {
          blocks.add(
            refer('await $_dioVar.fetch<${displayString(returnType)}>')
                .call([options])
                .assignFinal(_resultVar)
                .statement,
          );
          blocks.add(refer('$_resultVar.data')
              .asNoNullIf(returnNullable: returnType.isNullable)
              .assignFinal('value')
              .statement);
        } else if (returnType.toString() == 'dynamic') {
          blocks.add(
            refer('await $_dioVar.fetch').call([options]).assignFinal(_resultVar).statement,
          );
          blocks.add(Code('final value = $_resultVar.data;'));
        } else {
          final fetchType = returnType.isNullable ? 'Map<String,dynamic>?' : 'Map<String,dynamic>';
          blocks.add(
            refer('await $_dioVar.fetch<$fetchType>').call([options]).assignFinal(_resultVar).statement,
          );
          Expression mapperCode;
          switch (clientAnnotation.deserializer) {
            case dioxide.Parser.MapSerializable:
              mapperCode = refer('${displayString(returnType)}.fromMap($_resultVar.data!)');
              break;
            case dioxide.Parser.JsonSerializable:
              final genericArgumentFactories = isGenericArgumentFactories(returnType);

              var typeArgs = returnType is ParameterizedType ? returnType.typeArguments : [];

              if (typeArgs.length > 0 && genericArgumentFactories) {
                mapperCode = refer(
                    '${displayString(returnType)}.fromJson($_resultVar.data!,${_getInnerJsonSerializableMapperFn(returnType)})');
              } else {
                mapperCode = refer('${displayString(returnType)}.fromJson($_resultVar.data!)');
              }
              break;
            case dioxide.Parser.DartJsonMapper:
              mapperCode = refer('JsonMapper.fromMap<${displayString(returnType)}>($_resultVar.data!)!');
              break;
            case dioxide.Parser.DartSingleMapper:
              mapperCode = refer('''
              await ${clientAnnotation.compute ? 'compute(_dioxideDeserialize,' : '_dioxideDeserialize('}
                <String,dynamic>{
                  'resultType': '${displayString(returnType)}',
                  'data': $_resultVar.data!
                })''');
              break;
          }
          blocks.add(refer('$_resultVar.data')
              .conditionalIsNullIf(
                thisNullable: returnType.isNullable,
                whenFalse: mapperCode,
              )
              .assignFinal('value')
              .statement);
        }
      }
      if (isWrappered) {
        blocks.add(Code('''
      final httpResponse = HttpResponse(value, $_resultVar);
      $returnAsyncWrapper httpResponse;
      '''));
      } else {
        blocks.add(Code('$returnAsyncWrapper value as ${displayString(returnType)};'));
      }
    }

    return Block.of(blocks);
  }

  bool isGenericArgumentFactories(DartType? dartType) {
    final metaData = dartType?.element?.metadata;
    if (metaData == null || dartType == null) {
      return false;
    }
    final constDartObj = metaData.isNotEmpty ? metaData.first.computeConstantValue() : null;
    var genericArgumentFactories = false;
    if (constDartObj != null &&
        (!typeChecker(List).isExactlyType(dartType) && !typeChecker(BuiltList).isExactlyType(dartType))) {
      try {
        final annotation = ConstantReader(constDartObj);
        final obj = (annotation.peek('genericArgumentFactories'));
        // ignore: invalid_null_aware_operator
        genericArgumentFactories = obj?.boolValue ?? false;
      } catch (e) {}
    }

    return genericArgumentFactories;
  }

  String _getInnerJsonSerializableMapperFn(DartType dartType) {
    var typeArgs = dartType is ParameterizedType ? dartType.typeArguments : [];
    if (typeArgs.length > 0) {
      if (typeChecker(List).isExactlyType(dartType) || typeChecker(BuiltList).isExactlyType(dartType)) {
        var genericType = getResponseType(dartType);
        var typeArgs = genericType is ParameterizedType ? genericType.typeArguments : [];
        var mapperVal;

        var genericTypeString = '${displayString(genericType)}';

        if (typeArgs.length > 0 && isGenericArgumentFactories(genericType) && genericType != null) {
          mapperVal = '''
    (json)=> (json as List<dynamic>)
            .map<${genericTypeString}>((i) => ${genericTypeString}.fromJson(
                  i as Map<String,dynamic>,${_getInnerJsonSerializableMapperFn(genericType)}
                ))
            .toList(),
    ''';
        } else {
          if (isBasicType(genericType)) {
            mapperVal = '''
    (json)=>(json as List<dynamic>)
            .map<${genericTypeString}>((i) =>
                  i as ${genericTypeString}
                )
            .toList(),
    ''';
          } else {
            mapperVal = '''
    (json)=>(json as List<dynamic>)
            .map<${genericTypeString}>((i) =>
            ${genericTypeString == 'dynamic' ? ' i as Map<String,dynamic>' : genericTypeString + '.fromJson(  i as Map<String,dynamic> )  '}
    )
            .toList(),
    ''';
          }
        }
        return mapperVal;
      } else {
        var mappedVal = '';
        for (DartType arg in typeArgs) {
          // print(arg);
          var typeArgs = arg is ParameterizedType ? arg.typeArguments : [];
          if (typeArgs.length > 0) if (typeChecker(List).isExactlyType(arg) ||
              typeChecker(BuiltList).isExactlyType(arg)) {
            mappedVal += '${_getInnerJsonSerializableMapperFn(arg)}';
          } else {
            if (isGenericArgumentFactories(arg))
              mappedVal +=
                  '(json)=>${displayString(arg)}.fromJson(json as Map<String,dynamic>,${_getInnerJsonSerializableMapperFn(arg)}),';
            else
              mappedVal += '(json)=>${displayString(arg)}.fromJson(json as Map<String,dynamic>),';
          }
          else {
            mappedVal += '${_getInnerJsonSerializableMapperFn(arg)}';
          }
        }
        return mappedVal;
      }
    } else {
      if (displayString(dartType) == 'dynamic' || isBasicType(dartType)) {
        return '(json)=>json as ${displayString(dartType)},';
      } else {
        return '(json)=>${displayString(dartType)}.fromJson(json as Map<String,dynamic>),';
      }
    }
  }

  String _getInnerJsonDeSerializableMapperFn(DartType dartType) {
    var typeArgs = dartType is ParameterizedType ? dartType.typeArguments : [];
    if (typeArgs.length > 0) {
      if (typeChecker(List).isExactlyType(dartType) || typeChecker(BuiltList).isExactlyType(dartType)) {
        var genericType = getResponseType(dartType);
        var typeArgs = genericType is ParameterizedType ? genericType.typeArguments : [];
        var mapperVal;

        if (typeArgs.length > 0 && isGenericArgumentFactories(genericType) && genericType != null) {
          mapperVal = '(value) => value.map((value) => ${_getInnerJsonDeSerializableMapperFn(genericType)}).toList()';
        } else {
          if (isBasicType(genericType)) {
            mapperVal = '(value) => value';
          } else {
            mapperVal = '(value) => value.map((value) => value.toJson()).toList()';
          }
        }
        return mapperVal;
      } else {
        var mappedVal = '';
        for (DartType arg in typeArgs) {
          var typeArgs = arg is ParameterizedType ? arg.typeArguments : [];
          if (typeArgs.length > 0) if (typeChecker(List).isExactlyType(arg) ||
              typeChecker(BuiltList).isExactlyType(arg)) {
            mappedVal = '${_getInnerJsonDeSerializableMapperFn(arg)}';
          } else {
            if (isGenericArgumentFactories(arg))
              mappedVal = '(value) => value.toJson(${_getInnerJsonDeSerializableMapperFn(arg)})';
            else {
              mappedVal = '(value) => value';
            }
          }
          else {
            mappedVal = '${_getInnerJsonDeSerializableMapperFn(arg)}';
          }
        }
        return mappedVal;
      }
    } else {
      if (displayString(dartType) == 'dynamic' || isBasicType(dartType)) {
        return '(value) => value';
      } else {
        return '(value) => value.toJson()';
      }
    }
  }

  Expression _parseOptions(MethodElement m, Map<String, Expression> namedArguments, List<Code> blocks,
      Map<String, Expression> extraOptions) {
    final annoOptions = getAnnotation(m, dioxide.DioOptions);
    if (annoOptions == null) {
      final args = Map<String, Expression>.from(extraOptions)..addAll(namedArguments);
      final path = args.remove(_path)!;
      final dataVar = args.remove(_dataVar)!;
      final queryParams = args.remove(_queryParamsVar)!;
      final cancelToken = args.remove(_cancelToken);
      final sendProgress = args.remove(_onSendProgress);
      final receiveProgress = args.remove(_onReceiveProgress);

      final type = refer(displayString(getResponseType(m.returnType)));

      final composeArguments = <String, Expression>{_queryParamsVar: queryParams, _dataVar: dataVar};
      if (cancelToken != null) {
        composeArguments[_cancelToken] = cancelToken;
      }
      if (sendProgress != null) {
        composeArguments[_onSendProgress] = sendProgress;
      }
      if (receiveProgress != null) {
        composeArguments[_onReceiveProgress] = receiveProgress;
      }
      return refer('_setStreamType').call([
        refer('Options')
            .newInstance([], args)
            .property('compose')
            .call(
              [refer(_dioVar).property('options'), path],
              composeArguments,
            )
            .property('copyWith')
            .call(
                [],
                {}
                  ..addAll(buildBaseUrlOptions(extraOptions: args, dioRef: refer(_dioVar)))
                  ..addAll(buildTimeoutOptions(m)))
      ], {}, [
        type
      ]);
    } else {
      hasCustomOptions = true;
      blocks.add(
          refer('newRequestOptions').call([refer(annoOptions.item1.displayName)]).assignFinal('newOptions').statement);
      final newOptions = refer('newOptions');
      blocks.add(newOptions.property(_extraVar).property('addAll').call([extraOptions.remove(_extraVar)!]).statement);
      blocks.add(newOptions
          .property('headers')
          .property('addAll')
          .call([refer(_dioVar).property('options').property('headers')]).statement);
      blocks.add(newOptions.property('headers').property('addAll').call([extraOptions.remove('headers')!]).statement);
      return newOptions
          .property('copyWith')
          .call(
              [],
              Map.from(extraOptions)
                ..[_queryParamsVar] = namedArguments[_queryParamsVar]!
                ..[_path] = namedArguments[_path]!
                ..addAll(buildBaseUrlOptions(extraOptions: extraOptions, dioRef: refer(_dioVar)))
                ..addAll(buildTimeoutOptions(m)))
          .cascade('data')
          .assign(namedArguments[_dataVar]!);
    }
  }

  Method _generateOptionsCastMethod() {
    return Method((m) {
      m
        ..name = 'newRequestOptions'
        ..returns = refer('RequestOptions')

        /// required parameters
        ..requiredParameters.add(Parameter((p) {
          p.name = 'options';
          p.type = refer('Object?').type;
        }))

        /// add method body
        ..body = Code('''
         if (options is RequestOptions) {
            return options as RequestOptions;
          }
          if (options is Options) {
            return RequestOptions(
              method: options.method,
              sendTimeout: options.sendTimeout,
              receiveTimeout: options.receiveTimeout,
              extra: options.extra,
              headers: options.headers,
              responseType: options.responseType,
              contentType: options.contentType.toString(),
              validateStatus: options.validateStatus,
              receiveDataWhenStatusError: options.receiveDataWhenStatusError,
              followRedirects: options.followRedirects,
              maxRedirects: options.maxRedirects,
              requestEncoder: options.requestEncoder,
              responseDecoder: options.responseDecoder,
              path: '',
            );
          }
          return RequestOptions(path: '');
        ''');
    });
  }

  Method _generateTypeSetterMethod() {
    return Method((m) {
      final t = refer('T');
      final optionsParam = Parameter((p) {
        p
          ..name = 'requestOptions'
          ..type = refer('RequestOptions');
      });
      m
        ..name = '_setStreamType'
        ..types = ListBuilder([t])
        ..returns = refer('RequestOptions')
        ..requiredParameters = ListBuilder([optionsParam])
        ..body = Code('''if (T != dynamic &&
        !(requestOptions.responseType == ResponseType.bytes ||
            requestOptions.responseType == ResponseType.stream)) {
      if (T == String) {
        requestOptions.responseType = ResponseType.plain;
      } else {
        requestOptions.responseType = ResponseType.json;
      }
    }
    return requestOptions;''');
    });
  }

  Method _generateSerializeMethod() {
    return Method((m) {
      final t = refer('T');
      final optionsParam = Parameter((p) {
        p
          ..name = 'args'
          ..type = refer('Map<String,dynamic>');
      });
      m
        ..name = '_dioxideSerialize'
        ..types = ListBuilder([t])
        ..requiredParameters = ListBuilder([optionsParam])
        ..returns = refer('Future<T>')
        ..modifier = MethodModifier.async
        ..body = Code('''dynamic result = dioxideSerialize(args['dataType'] as String, args['data']);
    if (result is Future) {
      return await result as T;
    } else {
      return result as T;
    }''');
    });
  }

  Method _generateDeserializeMethod() {
    return Method((m) {
      final t = refer('T');
      final optionsParam = Parameter((p) {
        p
          ..name = 'args'
          ..type = refer('Map<String,dynamic>');
      });
      m
        ..name = '_dioxideDeserialize'
        ..types = ListBuilder([t])
        ..requiredParameters = ListBuilder([optionsParam])
        ..returns = refer('Future<T>')
        ..modifier = MethodModifier.async
        ..body = Code('''dynamic result = dioxideDeserialize(args['resultType'] as String, args['data']);
    if (result is Future) {
      return await result as T;
    } else {
      return result as T;
    }''');
    });
  }

  void _generateQueries(MethodElement m, List<Code> blocks, String _queryParamsVar) {
    final queries = getAnnotations(m, dioxide.Query);
    final queryParameters = queries.map((p, ConstantReader r) {
      final key = r.peek('value')?.stringValue ?? p.displayName;
      final Expression value;
      if (isBasicType(p.type) || p.type.isDartCoreList || p.type.isDartCoreMap) {
        value = refer(p.displayName);
      } else {
        switch (clientAnnotation.serializer) {
          case dioxide.Parser.JsonSerializable:
            value = p.type.nullabilitySuffix == NullabilitySuffix.question
                ? refer(p.displayName).nullSafeProperty('toJson').call([])
                : refer(p.displayName).property('toJson').call([]);
            break;
          case dioxide.Parser.MapSerializable:
            value = p.type.nullabilitySuffix == NullabilitySuffix.question
                ? refer(p.displayName).nullSafeProperty('toMap').call([])
                : refer(p.displayName).property('toMap').call([]);
            break;
          case dioxide.Parser.DartJsonMapper:
            value = refer(p.displayName);
            break;
          case dioxide.Parser.DartSingleMapper:
            value = refer('''
            await ${clientAnnotation.compute ? 'compute(_dioxideSerialize,' : '_dioxideSerialize('}
              <String,dynamic>{
                'dataType': '${displayString(p.type)}',
                'data': ${p.displayName}
              })''');
            break;
        }
      }
      return MapEntry(literalString(key, raw: true), value);
    });

    final queryMap = getAnnotations(m, dioxide.Queries);
    blocks.add(literalMap(queryParameters, refer('String'), refer('dynamic')).assignFinal(_queryParamsVar).statement);
    for (final p in queryMap.keys) {
      final type = p.type;
      final displayName = p.displayName;
      final Expression value;
      if (isBasicType(type) || type.isDartCoreList || type.isDartCoreMap) {
        value = refer(displayName);
      } else {
        switch (clientAnnotation.serializer) {
          case dioxide.Parser.JsonSerializable:
            value = p.type.nullabilitySuffix == NullabilitySuffix.question
                ? refer(displayName).nullSafeProperty('toJson').call([])
                : refer(displayName).property('toJson').call([]);
            break;
          case dioxide.Parser.MapSerializable:
            value = p.type.nullabilitySuffix == NullabilitySuffix.question
                ? refer(displayName).nullSafeProperty('toMap').call([])
                : refer(displayName).property('toMap').call([]);
            break;
          case dioxide.Parser.DartJsonMapper:
            value = refer(displayName);
            break;
          case dioxide.Parser.DartSingleMapper:
            value = refer('''
            await ${clientAnnotation.compute ? 'compute(_dioxideSerialize,' : '_dioxideSerialize('}
              <String,dynamic>{
                'dataType': '${displayString(p.type)}',
                'data': ${p.displayName}
              })''');
            break;
        }
      }

      /// workaround until this is merged in code_builder
      /// https://github.com/dart-lang/code_builder/pull/269
      final emitter = DartEmitter();
      final buffer = StringBuffer();
      value.accept(emitter, buffer);
      if (type.nullabilitySuffix == NullabilitySuffix.question) {
        refer('?? <String,dynamic>{}').accept(emitter, buffer);
      }
      final expression = refer(buffer.toString());

      blocks.add(refer('$_queryParamsVar.addAll').call([expression]).statement);
    }

    if (m.parameters.any((p) => (p.type.nullabilitySuffix == NullabilitySuffix.question))) {
      blocks.add(Code('$_queryParamsVar.removeWhere((k, v) => v == null);'));
    }
  }

  void _generateRequestBody(List<Code> blocks, String _dataVar, MethodElement m) {
    final _noBody = getMethodAnnotationByType(m, dioxide.NoBody);
    if (_noBody != null) {
      blocks.add(refer('null').assignFinal(_dataVar, refer('String?')).statement);
      return;
    }

    var annotation = getAnnotation(m, dioxide.Body);
    final _bodyName = annotation?.item1;
    if (_bodyName != null) {
      final nullToAbsent = annotation!.item2.peek('nullToAbsent')?.boolValue ?? false;
      final toFormData = annotation!.item2.peek('toFormData')?.boolValue ?? false;
      final bodyTypeElement = _bodyName.type.element;
      final _targetVar = toFormData ? _tempDataVar : _dataVar;
      if (TypeChecker.fromRuntime(Map).isAssignableFromType(_bodyName.type)) {
        blocks.add(literalMap({}, refer('String'), refer('dynamic')).assignFinal(_targetVar).statement);

        blocks.add(refer('$_targetVar.addAll').call([
          refer(
              '${_bodyName.displayName}${m.type.nullabilitySuffix == NullabilitySuffix.question ? ' ?? <String,dynamic>{}' : ''}')
        ]).statement);
        if (nullToAbsent) {
          blocks.add(Code('$_targetVar.removeWhere((k, v) => v == null);'));
        }
        if (toFormData) {
          blocks.add(refer('FormData.fromMap(${_targetVar})').assignFinal(_dataVar).statement);
        }
      } else if (bodyTypeElement != null &&
          ((typeChecker(List).isExactly(bodyTypeElement) || typeChecker(BuiltList).isExactly(bodyTypeElement)) &&
              !isBasicInnerType(_bodyName.type))) {
        switch (clientAnnotation.serializer) {
          case dioxide.Parser.JsonSerializable:
          case dioxide.Parser.DartJsonMapper:
            blocks.add(refer('''
            ${_bodyName.displayName}.map((e) => e.toJson()).toList()
            ''').assignFinal(_targetVar).statement);
            break;
          case dioxide.Parser.MapSerializable:
            blocks.add(refer('''
            ${_bodyName.displayName}.map((e) => e.toMap()).toList()
            ''').assignFinal(_targetVar).statement);
            break;
          case dioxide.Parser.DartSingleMapper:
            blocks.add(refer('''
            await ${clientAnnotation.compute ? 'compute(_dioxideSerialize,' : '_dioxideSerialize('}
              <String,dynamic>{
                 'dataType': '${displayString(genericOf(_bodyName.type))}',
                 'data': ${_bodyName.displayName}
              })''').assignFinal(_targetVar).statement);
            break;
        }
        if (toFormData) {
          blocks.add(refer('''FormData().addList('${_bodyName}', ${_targetVar})''').assignFinal(_dataVar).statement);
        }
      } else if (bodyTypeElement != null && typeChecker(File).isExactly(bodyTypeElement)) {
        blocks.add(refer('Stream')
            .property('fromIterable')
            .call([refer('${_bodyName.displayName}.readAsBytesSync().map((i)=>[i])')])
            .assignFinal(_dataVar)
            .statement);
      } else if (_bodyName.type.element is ClassElement) {
        final ele = _bodyName.type.element as ClassElement;
        if (clientAnnotation.serializer == dioxide.Parser.MapSerializable) {
          final toMap = ele.lookUpMethod('toMap', ele.library);
          if (toMap == null) {
            log.warning('${displayString(_bodyName.type)} must provide a `toMap()` method which return a Map.\n'
                'It is programmer\'s responsibility to make sure the ${_bodyName.type} is properly serialized');
            blocks.add(refer(_bodyName.displayName).assignFinal(_dataVar).statement);
          } else {
            blocks.add(literalMap({}, refer('String'), refer('dynamic')).assignFinal(_targetVar).statement);
            if (_bodyName.type.nullabilitySuffix != NullabilitySuffix.question) {
              blocks.add(refer('$_targetVar.addAll').call([refer('${_bodyName.displayName}.toMap()')]).statement);
            } else {
              blocks.add(refer('$_targetVar.addAll')
                  .call([refer('${_bodyName.displayName}?.toMap() ?? <String,dynamic>{}')]).statement);
            }
            if (toFormData) {
              blocks.add(refer('FormData.fromMap(${_targetVar})').assignFinal(_dataVar).statement);
            }
          }
        } else {
          if (_missingToJson(ele)) {
            log.warning('${displayString(_bodyName.type)} must provide a `toJson()` method which return a Map.\n'
                'It is programmer\'s responsibility to make sure the ${displayString(_bodyName.type)} is properly serialized');
            blocks.add(refer(_bodyName.displayName).assignFinal(_dataVar).statement);
          } else if (_missingSerialize(ele.enclosingElement, _bodyName.type)) {
            log.warning(
                '${displayString(_bodyName.type)} must provide a `serialize${displayString(_bodyName.type)}()` method which returns a Map.\n'
                'It is programmer\'s responsibility to make sure the ${displayString(_bodyName.type)} is properly serialized');
            blocks.add(refer(_bodyName.displayName).assignFinal(_dataVar).statement);
          } else {
            blocks.add(literalMap({}, refer('String'), refer('dynamic')).assignFinal(_targetVar).statement);

            final _bodyType = _bodyName.type;
            final genericArgumentFactories = isGenericArgumentFactories(_bodyType);

            var typeArgs = _bodyType is ParameterizedType ? _bodyType.typeArguments : [];

            String toJsonCode = '';
            if (typeArgs.isNotEmpty && genericArgumentFactories) {
              toJsonCode = _getInnerJsonDeSerializableMapperFn(_bodyType);
            }

            switch (clientAnnotation.serializer) {
              case dioxide.Parser.JsonSerializable:
              case dioxide.Parser.DartJsonMapper:
                if (_bodyName.type.nullabilitySuffix != NullabilitySuffix.question) {
                  blocks.add(refer('$_targetVar.addAll')
                      .call([refer('${_bodyName.displayName}.toJson($toJsonCode)')]).statement);
                } else {
                  blocks.add(refer('$_targetVar.addAll')
                      .call([refer('${_bodyName.displayName}?.toJson($toJsonCode) ?? <String,dynamic>{}')]).statement);
                }
                break;
              case dioxide.Parser.DartSingleMapper:
                if (_bodyName.type.nullabilitySuffix != NullabilitySuffix.question) {
                  blocks.add(refer('$_targetVar.addAll').call([
                    refer('''
                    await ${clientAnnotation.compute ? 'compute(_dioxideSerialize,' : '_dioxideSerialize('}
                      <String,dynamic>{
                        'dataType': '${displayString(_bodyName.type)}',
                        'data': ${_bodyName.displayName}
                      })''')
                  ]).statement);
                } else {
                  blocks.add(refer('$_targetVar.addAll').call([
                    refer('''${_bodyName.displayName} == null
                      ? <String,dynamic>{}
                      : await ${clientAnnotation.compute ? 'compute(_dioxideSerialize,' : '_dioxideSerialize('}
                        <String,dynamic>{
                          'dataType': '${displayString(_bodyName.type)}',
                          'data': ${_bodyName.displayName}
                      })''')
                  ]).statement);
                }
                break;
              case dioxide.Parser.MapSerializable:
                // Unreachable code
                break;
            }

            if (nullToAbsent) {
              blocks.add(Code('$_targetVar.removeWhere((k, v) => v == null);'));
            }
            if (toFormData) {
              blocks.add(refer('FormData.fromMap(${_targetVar})').assignFinal(_dataVar).statement);
            }
          }
        }
      } else {
        /// @Body annotations with no type are assinged as is
        blocks.add(refer(_bodyName.displayName).assignFinal(_dataVar).statement);
      }

      return;
    }

    var anyNullable = false;
    final fields = getAnnotations(m, dioxide.Field).map((p, r) {
      anyNullable |= p.type.nullabilitySuffix == NullabilitySuffix.question;
      final fieldName = r.peek('value')?.stringValue ?? p.displayName;
      final isFileField = typeChecker(File).isAssignableFromType(p.type);
      if (isFileField) {
        log.severe('File is not support by @Field(). Please use @Part() instead.');
      }
      return MapEntry(literal(fieldName), refer(p.displayName));
    });

    if (fields.isNotEmpty) {
      blocks.add(literalMap(fields).assignFinal(_dataVar).statement);
      if (anyNullable) {
        blocks.add(Code('$_dataVar.removeWhere((k, v) => v == null);'));
      }
      return;
    }

    final parts = getAnnotations(m, dioxide.Part);
    if (parts.isNotEmpty) {
      if (m.parameters.length == 1 && m.parameters.first.type.isDartCoreMap) {
        blocks.add(refer('FormData')
            .newInstanceNamed('fromMap', [CodeExpression(Code(m.parameters.first.displayName))])
            .assignFinal(_dataVar)
            .statement);
        return;
      } else if (m.parameters.length == 2 && m.parameters[1].type.isDartCoreMap) {
        blocks.add(refer('FormData')
            .newInstanceNamed('fromMap', [CodeExpression(Code(m.parameters[1].displayName))])
            .assignFinal(_dataVar)
            .statement);
        return;
      }
      blocks.add(refer('FormData').newInstance([]).assignFinal(_dataVar).statement);

      parts.forEach((p, r) {
        final fieldName = r.peek('name')?.stringValue ?? r.peek('value')?.stringValue ?? p.displayName;
        final isFileField = typeChecker(File).isAssignableFromType(p.type);
        final contentType = r.peek('contentType')?.stringValue;

        if (isFileField) {
          final fileNameValue = r.peek('fileName')?.stringValue;
          final fileName = fileNameValue != null
              ? literalString(fileNameValue)
              : refer(p.displayName).property('path.split(Platform.pathSeparator).last');

          final uploadFileInfo = refer('$MultipartFile.fromFileSync').call([
            refer(p.displayName).property('path')
          ], {
            'filename': fileName,
            if (contentType != null)
              'contentType': refer('MediaType', 'package:http_parser/http_parser.dart')
                  .property('parse')
                  .call([literal(contentType)])
          });

          final optinalFile =
              m.parameters.firstWhereOrNull((pp) => pp.displayName == p.displayName)?.isOptional ?? false;

          final returnCode = refer(_dataVar).property('files').property('add').call([
            refer('MapEntry').newInstance([literal(fieldName), uploadFileInfo])
          ]).statement;
          if (optinalFile) {
            final condication = refer(p.displayName).notEqualTo(literalNull).code;
            blocks.addAll([Code('if('), condication, Code(') {'), returnCode, Code('}')]);
          } else {
            blocks.add(returnCode);
          }
        } else if (displayString(p.type) == 'List<int>') {
          final optionalFile =
              m.parameters.firstWhereOrNull((pp) => pp.displayName == p.displayName)?.isOptional ?? false;
          final fileName = r.peek('fileName')?.stringValue;
          final conType = contentType == null ? '' : 'contentType: MediaType.parse(${literal(contentType)}),';
          final returnCode = refer(_dataVar).property('files').property('add').call([
            refer('''
                  MapEntry(
                '${fieldName}',
                MultipartFile.fromBytes(${p.displayName},

                filename:${literal(fileName ?? null)},
                    ${conType}
                    ))
                  ''')
          ]).statement;
          if (optionalFile) {
            final condition = refer(p.displayName).notEqualTo(literalNull).code;
            blocks.addAll([Code('if('), condition, Code(') {'), returnCode, Code('}')]);
          } else {
            blocks.add(returnCode);
          }
        } else if (typeChecker(List).isExactlyType(p.type) || typeChecker(BuiltList).isExactlyType(p.type)) {
          var innerType = genericOf(p.type);

          if (displayString(innerType) == 'List<int>') {
            final fileName = r.peek('fileName')?.stringValue;
            final conType = contentType == null ? '' : 'contentType: MediaType.parse(${literal(contentType)}),';
            blocks.add(refer(_dataVar).property('files').property('addAll').call([
              refer('''
                  ${p.displayName}.map((i) => MapEntry(
                '${fieldName}',
                MultipartFile.fromBytes(i,
                    filename:${literal(fileName ?? null)},
                    ${conType}
                    )))
                  ''')
            ]).statement);
          } else if (isBasicType(innerType) ||
              ((innerType != null) &&
                  (typeChecker(Map).isExactlyType(innerType) ||
                      typeChecker(BuiltMap).isExactlyType(innerType) ||
                      typeChecker(List).isExactlyType(innerType) ||
                      typeChecker(BuiltList).isExactlyType(innerType)))) {
            var value = isBasicType(innerType) ? 'i' : 'jsonEncode(i)';
            var nullableInfix = (p.type.nullabilitySuffix == NullabilitySuffix.question) ? '?' : '';
            blocks.add(refer('''
            ${p.displayName}$nullableInfix.forEach((i){
              ${_dataVar}.fields.add(MapEntry(${literal(fieldName)},${value}));
            })
            ''').statement);
          } else if (innerType != null && typeChecker(File).isExactlyType(innerType)) {
            final conType = contentType == null ? '' : 'contentType: MediaType.parse(${literal(contentType)}),';
            if (p.type.isNullable) {
              blocks.add(Code('if (${p.displayName} != null) {'));
            }
            blocks.add(refer(_dataVar).property('files').property('addAll').call([
              refer('''
                  ${p.displayName}.map((i) => MapEntry(
                '${fieldName}',
                MultipartFile.fromFileSync(i.path,
                    filename: i.path.split(Platform.pathSeparator).last,
                    ${conType}
                    )))
                  ''')
            ]).statement);
            if (p.type.isNullable) {
              blocks.add(Code('}'));
            }
          } else if (innerType != null && typeChecker(MultipartFile).isExactlyType(innerType)) {
            if (p.type.isNullable) {
              blocks.add(Code('if (${p.displayName} != null) {'));
            }
            blocks.add(refer(_dataVar).property('files').property('addAll').call([
              refer('''
                  ${p.displayName}.map((i) => MapEntry(
                '${fieldName}',
                i))
                  ''')
            ]).statement);
            if (p.type.isNullable) {
              blocks.add(Code('}'));
            }
          } else if (innerType?.element is ClassElement) {
            final ele = innerType!.element as ClassElement;
            if (_missingToJson(ele)) {
              throw Exception('toJson() method have to add to ${p.type}');
            } else {
              blocks.add(refer(_dataVar).property('fields').property('add').call([
                refer('MapEntry').newInstance([literal(fieldName), refer('jsonEncode(${p.displayName})')])
              ]).statement);
            }
          } else {
            throw Exception('Unknown error!');
          }
        } else if (isBasicType(p.type)) {
          if (p.type.nullabilitySuffix == NullabilitySuffix.question) {
            blocks.add(Code('if (${p.displayName} != null) {'));
          }
          blocks.add(refer(_dataVar).property('fields').property('add').call([
            refer('MapEntry').newInstance([
              literal(fieldName),
              if (typeChecker(String).isExactlyType(p.type))
                refer(p.displayName)
              else
                refer(p.displayName).property('toString').call([])
            ])
          ]).statement);
          if (p.type.nullabilitySuffix == NullabilitySuffix.question) {
            blocks.add(Code('}'));
          }
        } else if (typeChecker(Map).isExactlyType(p.type) || typeChecker(BuiltMap).isExactlyType(p.type)) {
          blocks.add(refer(_dataVar).property('fields').property('add').call([
            refer('MapEntry').newInstance([literal(fieldName), refer('jsonEncode(${p.displayName})')])
          ]).statement);
        } else if (p.type.element is ClassElement) {
          final ele = p.type.element as ClassElement;
          if (_missingToJson(ele)) {
            throw Exception('toJson() method have to add to ${p.type}');
          } else {
            blocks.add(refer(_dataVar).property('fields').property('add').call([
              refer('MapEntry').newInstance([
                literal(fieldName),
                refer(
                    'jsonEncode(${p.displayName}${p.type.nullabilitySuffix == NullabilitySuffix.question ? ' ?? <String,dynamic>{}' : ''})')
              ])
            ]).statement);
          }
        } else {
          blocks.add(refer(_dataVar).property('fields').property('add').call([
            refer('MapEntry').newInstance([literal(fieldName), refer(p.displayName)])
          ]).statement);
        }
      });
      return;
    }

    /// There is no body
    blocks.add(literalMap({}, refer('String'), refer('dynamic')).assignFinal(_dataVar).statement);
  }

  bool _missingToJson(ClassElement ele) {
    switch (clientAnnotation.serializer) {
      case dioxide.Parser.JsonSerializable:
      case dioxide.Parser.DartJsonMapper:
        final toJson = ele.lookUpMethod('toJson', ele.library);
        return toJson == null;
      case dioxide.Parser.MapSerializable:
      case dioxide.Parser.DartSingleMapper:
        return false;
    }
  }

  bool _missingSerialize(CompilationUnitElement ele, DartType type) {
    switch (clientAnnotation.serializer) {
      case dioxide.Parser.JsonSerializable:
      case dioxide.Parser.DartJsonMapper:
      case dioxide.Parser.MapSerializable:
        return false;
      case dioxide.Parser.DartSingleMapper:
        return !ele.functions.any((element) => element.name == 'dioxideDeserialize' && element.parameters.length == 1);
    }
  }
}

Builder generatorFactoryBuilder(BuilderOptions options) =>
    SharedPartBuilder([DioxideGenerator(DioxideOptions.fromOptions(options))], 'dioxide');
