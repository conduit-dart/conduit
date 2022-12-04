## 4.0.0

> Note: This release has breaking changes.

 - **BREAKING** **FEAT**: Column naming snake-case ([#153](https://github.com/conduit-dart/conduit/issues/153)). ([61e6ae77](https://github.com/conduit-dart/conduit/commit/61e6ae770e646db07fc8963d5fd9f599ab0cce5f))

## 3.2.11

 - **FIX**: Handle private class in isolate ([#152](https://github.com/conduit-dart/conduit/issues/152)). ([28b87457](https://github.com/conduit-dart/conduit/commit/28b87457498242e353301ebbde00c858dd265482))

## 3.2.10

 - **REFACTOR**: Uptick min dart version ([#139](https://github.com/conduit-dart/conduit/issues/139)). ([45723b81](https://github.com/conduit-dart/conduit/commit/45723b81f99259998dac08e1db3f5f8aa64f80dd))

## 3.2.9

 - **DOCS**: Sort out licensing and contributors ([#134](https://github.com/conduit-dart/conduit/issues/134)). ([1216ecf7](https://github.com/conduit-dart/conduit/commit/1216ecf7f83526004594634dddcf1df02d565a70))

## 3.2.8

 - **REFACTOR**: Apply standard lint analysis, refactor some nullables ([#129](https://github.com/conduit-dart/conduit/issues/129)). ([17f71bbb](https://github.com/conduit-dart/conduit/commit/17f71bbbe32cdb69947b6175f4ea46941be20410))

## 3.2.7

 - **REFACTOR**: Run analyzer and fix lint issues, possible perf improvements ([#128](https://github.com/conduit-dart/conduit/issues/128)). ([0675a4eb](https://github.com/conduit-dart/conduit/commit/0675a4ebe0e9e7574fed73c753f753d82c378cb9))

## 3.2.6

 - **REFACTOR**: Analyzer changes and publishing ([#127](https://github.com/conduit-dart/conduit/issues/127)). ([034ceb59](https://github.com/conduit-dart/conduit/commit/034ceb59542250553ff26695d1f8f10b0f3fd31b))

## 3.2.5

 - **DOCS**: Reworked contributions guide ([#126](https://github.com/conduit-dart/conduit/issues/126)). ([ce3847be](https://github.com/conduit-dart/conduit/commit/ce3847be9ef28b8be4f790f820cd085a8c910671))

## 3.2.4

 - **FIX**: Fix build binary command ([#121](https://github.com/conduit-dart/conduit/issues/121)). ([daba4b13](https://github.com/conduit-dart/conduit/commit/daba4b139558f429190acd530d76395bbe0e2405))

## 3.2.3

 - **FIX**: Upgrade to latest dependencies ([#120](https://github.com/conduit-dart/conduit/issues/120)). ([2be7f7aa](https://github.com/conduit-dart/conduit/commit/2be7f7aa6fb8085cd21956fead60dc8d10f5daf2))

## 3.2.2

 - **FIX**: Improve CI all unit tests ([#119](https://github.com/conduit-dart/conduit/issues/119)). ([a80d3d22](https://github.com/conduit-dart/conduit/commit/a80d3d22e176aecd2433e20bda5aac1f209bd6f3))

## 3.2.1

 - **FIX**: setup auto publishing pipeline format fixes. ([e94d6fb7](https://github.com/conduit-dart/conduit/commit/e94d6fb7f671c18ee347c851e62a85726db118ea))

## 3.2.1

 - **FIX**: setup auto publishing pipeline format fixes. ([b6124ee9](https://github.com/conduit-dart/conduit/commit/b6124ee9c9a578b5042e3c641373ddb45b1a5f17))

## 3.1.3

 - **REFACTOR**: use melos for mono-repo management. ([125099c5](https://github.com/conduit-dart/conduit/commit/125099c58e34e0e282c6fd0ec0cf0ec233bf92a1))

## 3.1.2

 - **REFACTOR**: use melos for mono-repo management. ([125099c5](https://github.com/conduit-dart/conduit/commit/125099c58e34e0e282c6fd0ec0cf0ec233bf92a1))

## 3.1.1

 - **REFACTOR**: use melos for mono-repo management.
 - **CHORE**: publish packages.

# 3.1.0

# 3.0.11

# 3.0.10

# 3.0.9

# 3.0.8

# 3.0.7
uptick version for multi release

# 3.0.5
Stable Conduit Release

# 2.0.0-b9
Fixed a bug with the conduit build command. We had left in dep overrides 
which should only be used for conduit internal dev.

# 2.0.0-b8
3rd attempt at first release.

# Conduit

# 2.0.0-b1

- Tooling works with conduit

# 2.0.0-a3
- broadened the version no. so works with any 2.0 version of conduit.
- Updated pubspec to pull conduit_test from pub.dev now that it is published.

## 2.0.0-a2

- Version bumps

## 2.0.0-a1

- Alpha release for Conduit NNBD included

# Conduit

## 1.0.1

- Fixes analysis warnings for Dart 2.1.1

## 1.0.0+1

- Bumps some dependency constraints to be more permissive

## 1.0.0

- Initial version from `package:conduit`.
- Adds `TestHarness` base class for test harnesses.
- Adds `TestHarnessORMMixin` for testing ORM applications.
- Adds `TestHarnessAuthMixin` for testing OAuth2 applications.
- Renames `TestClient` to `Agent` and adds methods for executing requests without constructing a `TestRequest`.
- Adds default parameters to `Agent` for its requests.
