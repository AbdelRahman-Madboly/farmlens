/// Lenient JSON readers: the node may send numbers as int, double or string.
double asDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

int asInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? double.tryParse(v.toString())?.toInt() ?? 0;
}

bool asBool(dynamic v) => v == true || v == 1 || v == 'true';
