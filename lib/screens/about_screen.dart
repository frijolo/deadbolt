import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:deadbolt/l10n/l10n.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aboutTitle),
      ),
      body: SafeArea(
        child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    l10n.loadingAppInfo,
                    style: TextStyle(color: cs.onSurface.withAlpha(178)),
                  ),
                ],
              ),
            );
          }

          final info = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                // App icon and name
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 96,
                    height: 96,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  info.appName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.bitcoinDescriptorAnalyzer,
                  style: TextStyle(
                    fontSize: 16,
                    color: cs.onSurface.withAlpha(178),
                  ),
                ),
                const SizedBox(height: 32),

                // Version info card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.versionLabel,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                        ),
                        Text(
                          '${info.version} (Build ${info.buildNumber})',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Project info card
                _buildInfoCard(
                  context,
                  title: l10n.projectSectionTitle,
                  children: [
                    _buildLinkRow(
                      context,
                      l10n.githubRepository,
                      'https://github.com/frijolo/deadbolt',
                      Icons.code,
                    ),
                    _buildLinkRow(
                      context,
                      l10n.securityGpg,
                      'https://github.com/frijolo/deadbolt/blob/master/SECURITY.md',
                      Icons.security,
                    ),
                    _buildInfoRow(context, l10n.licenseLabel, l10n.mitLicense),
                  ],
                ),
                const SizedBox(height: 32),

                // Copyright
                Text(
                  '© ${DateTime.now().year} Deadbolt',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withAlpha(97),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.openSourceDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withAlpha(97),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, {Color? labelColor}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: labelColor ?? cs.onSurface.withAlpha(178),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkRow(
    BuildContext context,
    String label,
    String url,
    IconData icon,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => _launchUrl(url),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(
                Icons.open_in_new,
                size: 16,
                color: cs.onSurface.withAlpha(97),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    final url = Uri.parse(urlString);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
