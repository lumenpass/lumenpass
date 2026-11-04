import 'package:flutter/material.dart';

import '../../../core/services/s3_service.dart';
import '../../../core/services/sftp_service.dart';
import '../../../core/services/webdav_service.dart';
import 's3_config_dialog.dart';
import 'sftp_config_dialog.dart';
import 'webdav_config_dialog.dart';

/// Pushes provider-configuration surfaces as full pages inside the fixed app
/// shell instead of dialogs.
///
/// These surfaces are deliberately built on `DcFlowPage`, which expects to own
/// the whole window. Wrapping them in `showDialog` produced a full-page layout
/// crammed into a dialog box. Pushing a route keeps the window frame constant
/// and gives the form the space it was designed for.
///
/// Each helper returns the connected account name, or `null` when the user
/// backs out without connecting.

Future<String?> pushWebDavConfigPage(
  BuildContext context, {
  WebDavConfig? initialConfig,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => WebDavConfigDialog(initialConfig: initialConfig),
    ),
  );
}

Future<String?> pushSftpConfigPage(
  BuildContext context, {
  SftpConfig? initialConfig,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => SftpConfigDialog(initialConfig: initialConfig),
    ),
  );
}

Future<String?> pushS3ConfigPage(
  BuildContext context, {
  S3Config? initialConfig,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => S3ConfigDialog(initialConfig: initialConfig),
    ),
  );
}
