import 'json_utils.dart';

class FusionSettings {
  final double w1;
  final double w2;
  final double theta;
  final String cropType;

  const FusionSettings({
    required this.w1,
    required this.w2,
    required this.theta,
    required this.cropType,
  });

  factory FusionSettings.fromJson(Map<String, dynamic> json) {
    return FusionSettings(
      w1: asDouble(json['w1']),
      w2: asDouble(json['w2']),
      theta: asDouble(json['theta']),
      cropType: json['crop_type']?.toString() ?? 'tomato',
    );
  }

  factory FusionSettings.defaults() {
    return const FusionSettings(
      w1: 0.6,
      w2: 0.4,
      theta: 0.5,
      cropType: 'tomato',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'w1': w1,
      'w2': w2,
      'theta': theta,
      'crop_type': cropType,
    };
  }

  FusionSettings copyWith({
    double? w1,
    double? w2,
    double? theta,
    String? cropType,
  }) {
    return FusionSettings(
      w1: w1 ?? this.w1,
      w2: w2 ?? this.w2,
      theta: theta ?? this.theta,
      cropType: cropType ?? this.cropType,
    );
  }
}