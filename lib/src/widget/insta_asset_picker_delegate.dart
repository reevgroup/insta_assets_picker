// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:insta_assets_picker/src/insta_assets_crop_controller.dart';
import 'package:insta_assets_picker/src/widget/crop_viewer.dart';
import 'package:provider/provider.dart';

import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// The reduced height of the crop view
const _kReducedCropViewHeight = 80;
const _kIndicatorSize = 20.0;

class InstaAssetPickerBuilder extends DefaultAssetPickerBuilderDelegate {
  InstaAssetPickerBuilder({
    required super.provider,
    required this.onCompleted,
    super.gridCount = 4,
    super.pickerTheme,
    super.textDelegate,
    this.title,
    this.initialCropParameters,
  }) : super(
          shouldRevertGrid: false,
          initialPermission: PermissionState.authorized,
          specialItemPosition: SpecialItemPosition.none,
        );

  final String? title;

  final List<InstaAssetsCrop>? initialCropParameters;

  final Function(Future<InstaAssetsExportDetails>) onCompleted;

  /// Save last position of the grid view scroll controller
  double _lastScrollOffset = 0.0;

  final ValueNotifier<double> _cropViewPosition = ValueNotifier<double>(0);
  final _cropViewerKey = GlobalKey<CropViewerState>();
  late final _cropController = InstaAssetsCropController(initialCropParameters);

  @override
  void initState(AssetPickerState<AssetEntity, AssetPathEntity> state) {
    super.initState(state);
  }

  @override
  void dispose() {
    _cropController.dispose();
    _cropViewPosition.dispose();
    super.dispose();
  }

  void onConfirm(BuildContext context) {
    Navigator.of(context).maybePop(provider.selectedAssets);
    _cropViewerKey.currentState?.saveCurrentCropChanges();
    onCompleted(_cropController.exportCropFiles());
  }

  @override
  Future<void> viewAsset(
    BuildContext context,
    int index,
    AssetEntity currentAsset,
  ) async {
    // if is preview asset, unselect it
    if (_cropController.previewAsset.value == currentAsset) {
      provider.unSelectAsset(currentAsset);
      _cropController.previewAsset.value =
          provider.selectedAssets.isEmpty ? null : provider.selectedAssets.last;
      return;
    }

    _cropController.previewAsset.value = currentAsset;
    provider.selectAsset(currentAsset);
  }

  @override
  Future<void> selectAsset(
    BuildContext context,
    AssetEntity asset,
    bool selected,
  ) async {
    final prevCount = provider.selectedAssets.length;
    await super.selectAsset(context, asset, selected);

    // update preview asset with selected
    final selectedAssets = provider.selectedAssets;
    if (prevCount < selectedAssets.length) {
      _cropController.previewAsset.value = asset;
    } else if (selected && asset == _cropController.previewAsset.value) {
      _cropController.previewAsset.value =
          selectedAssets.isEmpty ? null : selectedAssets.last;
    }
  }

  /// Handle scroll on grid view to hide/expand the crop view
  bool _handleScroll(
    BuildContext context,
    ScrollNotification notification,
    double position,
    double minHeight,
  ) {
    final scrollController = super.gridScrollController;
    final isScrollUp = scrollController.position.userScrollDirection ==
        ScrollDirection.reverse;
    final isScrollDown = scrollController.position.userScrollDirection ==
        ScrollDirection.forward;

    if (notification is ScrollEndNotification) {
      _lastScrollOffset = scrollController.offset;
      // NOTE: causes issue when spamming small scroll gestures
      // move _cropViewPosition to the closest limit (expanded or reduced)
      // if (position > minHeight && position < 0) {
      //   if (position <
      //       -MediaQuery.of(context).size.width + _kReducedCropViewHeight) {
      //     _cropViewPosition.value = minHeight;
      //   } else {
      //     _cropViewPosition.value = 0;
      //   }
      //   _lastScrollOffset = scrollController.offset;
      //   return true;
      // }
    }

    // expand crop view
    if (isScrollDown && scrollController.offset < 0 && position < 0) {
      _cropViewPosition.value = 0;
    } else if (isScrollUp &&
        (scrollController.offset - _lastScrollOffset) * 1.4 >
            MediaQuery.of(context).size.width - position &&
        position > minHeight) {
      // reduce crop view
      _cropViewPosition.value = MediaQuery.of(context).size.width -
          (scrollController.offset - _lastScrollOffset) * 1.4;
    }

    return true;
  }

  @override
  Widget pathEntitySelector(BuildContext context) {
    Widget selector(BuildContext context) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4)
            .copyWith(top: 4, bottom: 8),
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: theme.splashColor,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4).copyWith(left: 6),
          ),
          onPressed: () {
            Feedback.forTap(context);
            isSwitchingPath.value = !isSwitchingPath.value;
          },
          child: Selector<DefaultAssetPickerProvider,
              PathWrapper<AssetPathEntity>?>(
            selector: (_, DefaultAssetPickerProvider p) => p.currentPath,
            builder: (_, PathWrapper<AssetPathEntity>? p, Widget? w) => Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (p != null)
                  Flexible(
                    child: Text(
                      isPermissionLimited && p.path.isAll
                          ? textDelegate.accessiblePathName
                          : p.path.name,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                w!,
              ],
            ),
            child: ValueListenableBuilder<bool>(
              valueListenable: isSwitchingPath,
              builder: (_, bool isSwitchingPath, Widget? w) => Transform.rotate(
                angle: isSwitchingPath ? math.pi : 0,
                child: w,
              ),
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: theme.iconTheme.color,
              ),
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider<DefaultAssetPickerProvider>.value(
      value: provider,
      builder: (BuildContext c, _) => selector(c),
    );
  }

  @override
  Widget confirmButton(BuildContext context) {
    final Widget button = Consumer<DefaultAssetPickerProvider>(
      builder: (_, DefaultAssetPickerProvider p, __) {
        return TextButton(
          style: TextButton.styleFrom(
            foregroundColor:
                p.isSelectedNotEmpty ? themeColor : theme.dividerColor,
          ),
          onPressed: p.isSelectedNotEmpty ? () => onConfirm(context) : null,
          child: Text(
            p.isSelectedNotEmpty && !isSingleAssetMode
                ? '${textDelegate.confirm}'
                    ' (${p.selectedAssets.length}/${p.maxAssets})'
                : textDelegate.confirm,
          ),
        );
      },
    );
    return ChangeNotifierProvider<DefaultAssetPickerProvider>.value(
      value: provider,
      builder: (_, __) => button,
    );
  }

  @override
  Widget androidLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: title != null ? Text(title!) : null,
        leading: Transform.translate(
          offset: const Offset(-8, 0),
          child: backButton(context),
        ),
        actions: <Widget>[confirmButton(context)],
      ),
      body: ChangeNotifierProvider<DefaultAssetPickerProvider>.value(
        value: provider,
        builder: (BuildContext context, _) {
          return Stack(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: _cropViewPosition,
                builder: (context, position, child) {
                  final minHeight = -(MediaQuery.of(context).size.width -
                      _kReducedCropViewHeight);

                  return AnimatedPositioned(
                    top: position.clamp(minHeight, 0),
                    duration: position == 0
                        ? const Duration(milliseconds: 250)
                        : Duration.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Listener(
                          onPointerDown: (_) => _cropViewPosition.value = 0,
                          child: CropViewer(
                            key: _cropViewerKey,
                            controller: _cropController,
                            provider: provider,
                            theme: pickerTheme,
                          ),
                        ),
                        pathEntitySelector(context),
                        SizedBox(
                          height: MediaQuery.of(context).size.height -
                              kToolbarHeight -
                              _kReducedCropViewHeight,
                          width: MediaQuery.of(context).size.width,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (ScrollNotification notification) =>
                                _handleScroll(
                              context,
                              notification,
                              position,
                              minHeight,
                            ),
                            child: _buildGrid(context),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              pathEntityListBackdrop(context),
              _buildListAlbums(context),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget appleOSLayout(BuildContext context) => androidLayout(context);

  Widget _buildListAlbums(context) {
    return Consumer<DefaultAssetPickerProvider>(
      builder: (BuildContext context, _, __) => MediaQuery(
        // fix: https://github.com/fluttercandies/flutter_wechat_assets_picker/issues/395
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: -kToolbarHeight),
        ),
        child: Builder(
          builder: (BuildContext context) => pathEntityListWidget(context),
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    return Consumer<DefaultAssetPickerProvider>(
      builder: (BuildContext context, DefaultAssetPickerProvider p, __) {
        final bool shouldDisplayAssets =
            p.hasAssetsToDisplay || shouldBuildSpecialItem;
        // when asset list is available and no asset is selected,
        // select the first of the list
        if (shouldDisplayAssets && p.selectedAssets.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final list =
                await p.currentPath?.path.getAssetListRange(start: 0, end: 1);
            if (list?.isNotEmpty ?? false) {
              p.selectAsset(list!.first);
              _cropController.previewAsset.value = list.first;
            }
          });
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: shouldDisplayAssets
              ? MediaQuery(
                  // fix: https://github.com/fluttercandies/flutter_wechat_assets_picker/issues/395
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: -kToolbarHeight),
                  ),
                  child: RepaintBoundary(child: assetsGridBuilder(context)),
                )
              : loadingIndicator(context),
        );
      },
    );
  }

  /// To show selected assets indicator and preview asset overlay
  @override
  Widget selectIndicator(BuildContext context, int index, AssetEntity asset) {
    final selectedAssets = provider.selectedAssets;
    final Duration duration = switchingPathDuration * 0.75;

    final int indexSelected = selectedAssets.indexOf(asset);
    final bool isSelected = indexSelected != -1;

    final Widget innerSelector = AnimatedContainer(
      duration: duration,
      width: _kIndicatorSize,
      height: _kIndicatorSize,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.selectedRowColor, width: 1),
        color: isSelected ? themeColor : Colors.black.withOpacity(.30),
        shape: BoxShape.circle,
      ),
      child: FittedBox(
        child: AnimatedSwitcher(
          duration: duration,
          reverseDuration: duration,
          child: isSelected
              ? Text((indexSelected + 1).toString())
              : const SizedBox.shrink(),
        ),
      ),
    );

    return ValueListenableBuilder<AssetEntity?>(
      valueListenable: _cropController.previewAsset,
      builder: (context, previewAsset, child) {
        final bool isPreview = asset == _cropController.previewAsset.value;

        return Positioned.fill(
          child: GestureDetector(
            onTap: isPreviewEnabled
                ? () => viewAsset(context, index, asset)
                : null,
            child: AnimatedContainer(
              duration: switchingPathDuration,
              padding: const EdgeInsets.all(4),
              color: isPreview
                  ? theme.selectedRowColor.withOpacity(.5)
                  : theme.backgroundColor.withOpacity(.1),
              child: isSelected && !isSingleAssetMode
                  ? Align(
                      alignment: AlignmentDirectional.topEnd,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => selectAsset(context, asset, isSelected),
                        child: innerSelector,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget selectedBackdrop(BuildContext context, int index, AssetEntity asset) =>
      const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Theme(
        data: theme,
        child: Material(
          color: theme.canvasColor,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (isAppleOS) appleOSLayout(context) else androidLayout(context),
              if (Platform.isIOS) iOSPermissionOverlay(context),
            ],
          ),
        ),
      ),
    );
  }
}