const List<_AwsRegion> kAwsRegions = [
  _AwsRegion('us-east-1', 'US East (N. Virginia)'),
  _AwsRegion('us-east-2', 'US East (Ohio)'),
  _AwsRegion('us-west-1', 'US West (N. California)'),
  _AwsRegion('us-west-2', 'US West (Oregon)'),
  _AwsRegion('af-south-1', 'Africa (Cape Town)'),
  _AwsRegion('ap-east-1', 'Asia Pacific (Hong Kong)'),
  _AwsRegion('ap-south-1', 'Asia Pacific (Mumbai)'),
  _AwsRegion('ap-south-2', 'Asia Pacific (Hyderabad)'),
  _AwsRegion('ap-southeast-1', 'Asia Pacific (Singapore)'),
  _AwsRegion('ap-southeast-2', 'Asia Pacific (Sydney)'),
  _AwsRegion('ap-southeast-3', 'Asia Pacific (Jakarta)'),
  _AwsRegion('ap-southeast-4', 'Asia Pacific (Melbourne)'),
  _AwsRegion('ap-southeast-5', 'Asia Pacific (Malaysia)'),
  _AwsRegion('ap-southeast-7', 'Asia Pacific (Thailand)'),
  _AwsRegion('ap-northeast-1', 'Asia Pacific (Tokyo)'),
  _AwsRegion('ap-northeast-2', 'Asia Pacific (Seoul)'),
  _AwsRegion('ap-northeast-3', 'Asia Pacific (Osaka)'),
  _AwsRegion('ca-central-1', 'Canada (Central)'),
  _AwsRegion('ca-west-1', 'Canada West (Calgary)'),
  _AwsRegion('eu-central-1', 'Europe (Frankfurt)'),
  _AwsRegion('eu-central-2', 'Europe (Zurich)'),
  _AwsRegion('eu-west-1', 'Europe (Ireland)'),
  _AwsRegion('eu-west-2', 'Europe (London)'),
  _AwsRegion('eu-west-3', 'Europe (Paris)'),
  _AwsRegion('eu-south-1', 'Europe (Milan)'),
  _AwsRegion('eu-south-2', 'Europe (Spain)'),
  _AwsRegion('eu-north-1', 'Europe (Stockholm)'),
  _AwsRegion('il-central-1', 'Israel (Tel Aviv)'),
  _AwsRegion('me-south-1', 'Middle East (Bahrain)'),
  _AwsRegion('me-central-1', 'Middle East (UAE)'),
  _AwsRegion('mx-central-1', 'Mexico (Central)'),
  _AwsRegion('sa-east-1', 'South America (São Paulo)'),
  _AwsRegion('us-gov-east-1', 'AWS GovCloud (US-East)'),
  _AwsRegion('us-gov-west-1', 'AWS GovCloud (US-West)'),
];

class _AwsRegion {
  final String code;
  final String label;

  const _AwsRegion(this.code, this.label);
}

String? regionCodeByLabel(String label) {
  for (final r in kAwsRegions) {
    if (r.label == label) return r.code;
  }
  return null;
}

String? regionLabelByCode(String code) {
  for (final r in kAwsRegions) {
    if (r.code == code) return r.label;
  }
  return null;
}
