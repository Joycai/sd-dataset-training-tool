import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dataset_training_tool/models/ai_tagger_models.dart';
import 'package:dataset_training_tool/services/ai_tagger_service.dart';

void main() {
  group('AiServerConfig', () {
    test('parses /getconfig response', () {
      final json = jsonDecode('''
      {
        "Interrogators": [
          {"ModelName": "SmilingWolf/wd-swinv2-tagger-v3",
           "SupportedVideo": false,
           "RepositoryLink": "https://huggingface.co/SmilingWolf/wd-swinv2-tagger-v3"}
        ],
        "Editors": [],
        "Translators": []
      }
      ''') as Map<String, dynamic>;

      final config = AiServerConfig.fromJson(json);
      expect(config.interrogators, hasLength(1));
      expect(config.interrogators.first.modelName,
          'SmilingWolf/wd-swinv2-tagger-v3');
      expect(config.editors, isEmpty);
      expect(config.translators, isEmpty);
    });
  });

  group('AiModelParams', () {
    test('parses /getmodelparams response and reads threshold', () {
      final json = jsonDecode('''
      { "Success": true, "ErrorMessage": "", "Type": "wd",
        "Parameters": [
          {"Key": "threshold", "Value": "0.35", "Type": "float1", "Comment": ""}
        ] }
      ''') as Map<String, dynamic>;

      final params = AiModelParams.fromJson(json);
      expect(params.success, isTrue);
      expect(params.type, 'wd');
      expect(params.threshold, 0.35);
    });

    test('threshold is null when absent', () {
      final params = AiModelParams.fromJson(const {
        'Success': true,
        'ErrorMessage': '',
        'Type': 'florence2',
        'Parameters': <dynamic>[],
      });
      expect(params.threshold, isNull);
    });
  });

  group('AiModelRequest', () {
    test('wd factory serializes threshold as float1', () {
      final req = AiModelRequest.wd(
        modelName: 'SmilingWolf/wd-swinv2-tagger-v3',
        threshold: 0.25,
      );
      expect(req.toJson(), {
        'ModelName': 'SmilingWolf/wd-swinv2-tagger-v3',
        'AdditionalParameters': [
          {'Key': 'threshold', 'Value': '0.25', 'Type': 'float1', 'Comment': ''}
        ],
      });
    });

    test('wd factory omits parameters when threshold is null', () {
      final req = AiModelRequest.wd(modelName: 'm');
      expect((req.toJson()['AdditionalParameters'] as List), isEmpty);
    });
  });

  group('AiInterrogateResponse', () {
    test('parses response and de-duplicates tags across models', () {
      final json = jsonDecode('''
      {
        "Success": true,
        "ErrorMessage": "Image successfully processed.",
        "Result": [
          { "ModelName": "a",
            "Tags": [ {"Tag": "1girl", "Probability": 0.99},
                      {"Tag": "long_hair", "Probability": 0.9} ] },
          { "ModelName": "b",
            "Tags": [ {"Tag": "1girl", "Probability": 0.95},
                      {"Tag": "smile", "Probability": 0.8} ] }
        ]
      }
      ''') as Map<String, dynamic>;

      final resp = AiInterrogateResponse.fromJson(json);
      expect(resp.success, isTrue);
      expect(resp.results, hasLength(2));
      expect(resp.allTags, ['1girl', 'long_hair', 'smile']);
    });
  });

  group('AiTaggerService.normalizeTag', () {
    test('converts underscores to spaces by default', () {
      expect(AiTaggerService.normalizeTag('long_hair'), 'long hair');
    });

    test('keeps underscores when requested', () {
      expect(
        AiTaggerService.normalizeTag('long_hair',
            underscoreStyle: TagUnderscoreStyle.keep),
        'long_hair',
      );
    });

    test('escapes parentheses when requested', () {
      expect(
        AiTaggerService.normalizeTag('smile (expression)',
            escapeParentheses: true),
        r'smile \(expression\)',
      );
    });

    test('trims whitespace', () {
      expect(AiTaggerService.normalizeTag('  solo  '), 'solo');
    });
  });
}
