import 'package:flutter/material.dart';
import '../../models/iptv/iptv_models.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/iptv/iptv_settings.dart';
import '../../services/theme/design_tokens.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/tab_strip.dart';
import '../../widgets/iptv/iptv_channel_card.dart';
import 'iptv_channel_sheet.dart';

class IptvSearchPage extends StatefulWidget {
  final List<QuickChannel> quickChannels;

  const IptvSearchPage({super.key, this.quickChannels = const []});

  @override
  State<IptvSearchPage> createState() => _IptvSearchPageState();
}

class _IptvSearchPageState extends State<IptvSearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    'Combat',
    'Racing',
    'Sports',
    'Movies',
    'News',
    'Arabic',
    'Discovery',
    'Kids',
    'US',
    'UK',
    'CA',
    'Bay Area',
    'Int. Sports',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<HardcodedChannel> _filteredChannels() {
    final q = _query.toLowerCase();
    final results = <HardcodedChannel>[];

    // Search hardcoded channels
    for (final c in HardcodedChannels.all) {
      final matchesCategory = _selectedCategory == 'All' || c.category == _selectedCategory;
      if (!matchesCategory) continue;
      if (_query.trim().isEmpty) {
        results.add(c);
        continue;
      }
      if (c.name.toLowerCase().contains(q) ||
          c.short.toLowerCase().contains(q) ||
          c.keywords.any((k) => k.toLowerCase().contains(q))) {
        results.add(c);
      }
    }

    // Also search user-added Quick Channels
    for (final qc in widget.quickChannels) {
      if (_selectedCategory != 'All' && qc.category != _selectedCategory) continue;
      if (_query.trim().isEmpty) {
        results.add(_toHardcoded(qc));
        continue;
      }
      if (qc.name.toLowerCase().contains(q) ||
          qc.short.toLowerCase().contains(q) ||
          qc.keywords.any((k) => k.toLowerCase().contains(q))) {
        results.add(_toHardcoded(qc));
      }
    }

    return results;
  }

  static HardcodedChannel _toHardcoded(QuickChannel ch) => HardcodedChannel(
        id: 'qc_${ch.id}',
        name: ch.name,
        short: ch.short,
        category: ch.category,
        keywords: ch.keywords,
        gradient: ch.gradient,
        iconUrl: ch.iconUrl,
      );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final channels = _filteredChannels();
    final width = MediaQuery.sizeOf(context).width;
    // This is a pushed route, not a shell slot: the shell's blended nav is not
    // painted over it, so the page's own header is the top chrome and it pays
    // the device's status strip itself.
    final topPadding = MediaQuery.paddingOf(context).top;

    // Responsive columns
    int crossAxisCount = 2;
    if (width > 1200) {
      crossAxisCount = 6;
    } else if (width > 900) {
      crossAxisCount = 5;
    } else if (width > 600) {
      crossAxisCount = 4;
    } else if (width > 420) {
      crossAxisCount = 3;
    }

    final content = Column(
      children: [
        // The header is transparent, with the canvas behind it. It used to be
        // an `AppBar` on an opaque `tokens.bg` fill with a `tokens.hairline`
        // under it - the opaque band the blended shell nav exists to remove -
        // and `AppBar`'s toolbar is deliberately excluded from directional
        // traversal, so the field inside it was never reachable from a remote.
        // A plain row is a layout contract and imposes nothing on focus.
        Padding(
          padding: EdgeInsets.fromLTRB(
            ZplaySpacing.s8,
            topPadding + ZplaySpacing.s8,
            ZplaySpacing.s16,
            ZplaySpacing.s8,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                color: tokens.textPrimary,
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: ZplaySpacing.s4),
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: ZplayRadius.mdAll,
                    border: Border.fromBorderSide(tokens.hairline),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: ZplayType.body.toStyle(color: tokens.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search 60+ live channels, leagues, networks…',
                      hintStyle: ZplayType.label.toStyle(color: tokens.textMuted),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: tokens.accent,
                        size: 20,
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: tokens.textMuted,
                                size: 18,
                              ),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    onChanged: (val) => setState(() => _query = val),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Category filter. The hand-rolled row of bordered, filled pills is
        // gone: `TabStrip` paints no fill in either state, marks the selection
        // with a short accent bar under the label, and draws `CardFocusRing` as
        // the only edge - which is the one control language the rest of the app
        // uses.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZplaySpacing.s20),
          child: TabStrip<String>(
            options: [
              for (final cat in _categories)
                TabStripOption<String>(value: cat, label: cat),
            ],
            selected: _selectedCategory,
            onSelected: (cat) => setState(() => _selectedCategory = cat),
            semanticsLabel: 'Channel categories',
            height: 44,
          ),
        ),

        // Channel Grid
        Expanded(
          child: channels.isEmpty
              ? Center(
                  child: Text(
                    'No channels match your search.',
                    style: ZplayType.body.toStyle(color: tokens.textMuted),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    ZplaySpacing.s20,
                    ZplaySpacing.s12,
                    ZplaySpacing.s20,
                    30,
                  ),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: ZplaySpacing.s16,
                  ),
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final ch = channels[index];
                    return IptvChannelCard(
                      channel: ch,
                      onTap: () => IptvChannelSheet.show(context, ch),
                    );
                  },
                ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      // One canvas under the whole page, gated on the same ambient-lights
      // setting the Live TV vertical itself reads, so the two agree about what
      // the app's background is.
      body: IptvSettings.enableAmbientLights.value
          ? AnimatedAmbientBackground(child: content)
          : content,
    );
  }
}
