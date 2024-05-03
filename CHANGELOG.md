# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2024-05-03

### Changes

---

Packages with breaking changes:

 - [`conduit_runtime` - `v5.0.3`](#conduit_runtime---v503)
 - [`conduit_test` - `v5.0.3`](#conduit_test---v503)

Packages with other changes:

 - [`conduit` - `v5.0.3`](#conduit---v503)
 - [`conduit_codable` - `v5.0.3`](#conduit_codable---v503)
 - [`conduit_common` - `v5.0.3`](#conduit_common---v503)
 - [`conduit_config` - `v5.0.3`](#conduit_config---v503)
 - [`conduit_core` - `v5.0.3`](#conduit_core---v503)
 - [`conduit_isolate_exec` - `v5.0.3`](#conduit_isolate_exec---v503)
 - [`conduit_open_api` - `v5.0.3`](#conduit_open_api---v503)
 - [`conduit_password_hash` - `v5.0.3`](#conduit_password_hash---v503)
 - [`conduit_postgresql` - `v5.0.3`](#conduit_postgresql---v503)
 - [`fs_test_agent` - `v5.0.3`](#fs_test_agent---v503)

---

#### `conduit_runtime` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **REFACTOR**: Limit ci runs and uptick lint package ([#160](https://github.com/conduit-dart/conduit/issues/160)). ([f8d1de60](https://github.com/conduit-dart/conduit/commit/f8d1de600bc66f02827789b5baed3c35abbd2d27))
 - **REFACTOR**: Uptick min dart version ([#139](https://github.com/conduit-dart/conduit/issues/139)). ([45723b81](https://github.com/conduit-dart/conduit/commit/45723b81f99259998dac08e1db3f5f8aa64f80dd))
 - **REFACTOR**: Apply standard lint analysis, refactor some nullables ([#129](https://github.com/conduit-dart/conduit/issues/129)). ([17f71bbb](https://github.com/conduit-dart/conduit/commit/17f71bbbe32cdb69947b6175f4ea46941be20410))
 - **REFACTOR**: Run analyzer and fix lint issues, possible perf improvements ([#128](https://github.com/conduit-dart/conduit/issues/128)). ([0675a4eb](https://github.com/conduit-dart/conduit/commit/0675a4ebe0e9e7574fed73c753f753d82c378cb9))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: conduit try resolve lib folder instead package library ([#176](https://github.com/conduit-dart/conduit/issues/176)). ([02390962](https://github.com/conduit-dart/conduit/commit/02390962721bd21632dee60953e6b06e71477add))
 - **FIX**: Handle private class in isolate ([#152](https://github.com/conduit-dart/conduit/issues/152)). ([28b87457](https://github.com/conduit-dart/conduit/commit/28b87457498242e353301ebbde00c858dd265482))
 - **FIX**(cli): Fix build binary command ([#121](https://github.com/conduit-dart/conduit/issues/121)). ([daba4b13](https://github.com/conduit-dart/conduit/commit/daba4b139558f429190acd530d76395bbe0e2405))
 - **FIX**: Upgrade to latest dependencies ([#120](https://github.com/conduit-dart/conduit/issues/120)). ([2be7f7aa](https://github.com/conduit-dart/conduit/commit/2be7f7aa6fb8085cd21956fead60dc8d10f5daf2))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **FEAT**: Works with latest version of dart (2.19), CI works, websockets fixed, melos tasks added:wq. ([616a99be](https://github.com/conduit-dart/conduit/commit/616a99be9624b34c0a01acd7ff4a67b0d8b9a75f))
 - **DOCS**: improve doc gen ([#180](https://github.com/conduit-dart/conduit/issues/180)). ([8d18f872](https://github.com/conduit-dart/conduit/commit/8d18f872fa70ceec3052077c0e6adbc6c7ac6953))
 - **DOCS**: Add doc generation and housekeeping ([#156](https://github.com/conduit-dart/conduit/issues/156)). ([89f303c8](https://github.com/conduit-dart/conduit/commit/89f303c88251ec2228e58d807fc553839c3c967d))
 - **BREAKING** **FEAT**: Column naming snake-case ([#153](https://github.com/conduit-dart/conduit/issues/153)). ([61e6ae77](https://github.com/conduit-dart/conduit/commit/61e6ae770e646db07fc8963d5fd9f599ab0cce5f))

#### `conduit_test` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: Remove common test. ([cebcc417](https://github.com/conduit-dart/conduit/commit/cebcc417fc2849f18b7e9a2a1bbab412eda621ff))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **REFACTOR**: Uptick min dart version ([#139](https://github.com/conduit-dart/conduit/issues/139)). ([45723b81](https://github.com/conduit-dart/conduit/commit/45723b81f99259998dac08e1db3f5f8aa64f80dd))
 - **REFACTOR**: Apply standard lint analysis, refactor some nullables ([#129](https://github.com/conduit-dart/conduit/issues/129)). ([17f71bbb](https://github.com/conduit-dart/conduit/commit/17f71bbbe32cdb69947b6175f4ea46941be20410))
 - **REFACTOR**: Analyzer changes and publishing ([#127](https://github.com/conduit-dart/conduit/issues/127)). ([034ceb59](https://github.com/conduit-dart/conduit/commit/034ceb59542250553ff26695d1f8f10b0f3fd31b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: Handle private class in isolate ([#152](https://github.com/conduit-dart/conduit/issues/152)). ([28b87457](https://github.com/conduit-dart/conduit/commit/28b87457498242e353301ebbde00c858dd265482))
 - **FIX**(cli): Fix build binary command ([#121](https://github.com/conduit-dart/conduit/issues/121)). ([daba4b13](https://github.com/conduit-dart/conduit/commit/daba4b139558f429190acd530d76395bbe0e2405))
 - **FIX**: Upgrade to latest dependencies ([#120](https://github.com/conduit-dart/conduit/issues/120)). ([2be7f7aa](https://github.com/conduit-dart/conduit/commit/2be7f7aa6fb8085cd21956fead60dc8d10f5daf2))
 - **FIX**(ci): setup auto publishing pipeline format fixes. ([42266ade](https://github.com/conduit-dart/conduit/commit/42266ade0cd3101b1b2a9eb0cf2bc206a1b5a42d))
 - **FIX**(ci): setup auto publishing pipeline format fixes. ([bd29f1f4](https://github.com/conduit-dart/conduit/commit/bd29f1f4c5a963041cdb498fd5ecbdf6ccd109a7))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **DOCS**: improve doc gen ([#180](https://github.com/conduit-dart/conduit/issues/180)). ([8d18f872](https://github.com/conduit-dart/conduit/commit/8d18f872fa70ceec3052077c0e6adbc6c7ac6953))
 - **DOCS**: Add doc generation and housekeeping ([#156](https://github.com/conduit-dart/conduit/issues/156)). ([89f303c8](https://github.com/conduit-dart/conduit/commit/89f303c88251ec2228e58d807fc553839c3c967d))
 - **DOCS**: Sort out licensing and contributors ([#134](https://github.com/conduit-dart/conduit/issues/134)). ([1216ecf7](https://github.com/conduit-dart/conduit/commit/1216ecf7f83526004594634dddcf1df02d565a70))
 - **BREAKING** **FEAT**: Column naming snake-case ([#153](https://github.com/conduit-dart/conduit/issues/153)). ([61e6ae77](https://github.com/conduit-dart/conduit/commit/61e6ae770e646db07fc8963d5fd9f599ab0cce5f))

#### `conduit` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: Remove common test. ([cebcc417](https://github.com/conduit-dart/conduit/commit/cebcc417fc2849f18b7e9a2a1bbab412eda621ff))
 - **REFACTOR**: Remove pub_cache ([#188](https://github.com/conduit-dart/conduit/issues/188)). ([6d5beca1](https://github.com/conduit-dart/conduit/commit/6d5beca119fceaa7938402f171fc8983678c40b3))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([00cc11e6](https://github.com/conduit-dart/conduit/commit/00cc11e6ac20f7c9274e3296294f64db62104e62))
 - **FIX**(ci): trigger. ([cfd406c0](https://github.com/conduit-dart/conduit/commit/cfd406c07b1595316061ac5840b4625e4503f13a))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: catch no templates scenario ([#181](https://github.com/conduit-dart/conduit/issues/181)). ([eaeecc4d](https://github.com/conduit-dart/conduit/commit/eaeecc4df649ef6fcd90451e8c80cadbb11af7e8))
 - **FIX**: Cache cli ([#169](https://github.com/conduit-dart/conduit/issues/169)). ([8dd84221](https://github.com/conduit-dart/conduit/commit/8dd842210e117dcd63c3c1fe6ce5045389cd5b2f))
 - **FIX**: investigate build issues ([#167](https://github.com/conduit-dart/conduit/issues/167)). ([ee79f9e6](https://github.com/conduit-dart/conduit/commit/ee79f9e69a4f6dbaefa93db78505eaf7b5a88652))
 - **FIX**: Check cli integrity ([#164](https://github.com/conduit-dart/conduit/issues/164)). ([5fd4e403](https://github.com/conduit-dart/conduit/commit/5fd4e4036d7316c91c2bfac3a06a2526096a9fac))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Replace ServiceRegistry with Finalizers ([#185](https://github.com/conduit-dart/conduit/issues/185)). ([73208e92](https://github.com/conduit-dart/conduit/commit/73208e92ceed79369405933b20d98c9ed48ed0e5))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **DOCS**: improve doc gen ([#180](https://github.com/conduit-dart/conduit/issues/180)). ([8d18f872](https://github.com/conduit-dart/conduit/commit/8d18f872fa70ceec3052077c0e6adbc6c7ac6953))

#### `conduit_codable` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **REFACTOR**: Limit ci runs and uptick lint package ([#160](https://github.com/conduit-dart/conduit/issues/160)). ([f8d1de60](https://github.com/conduit-dart/conduit/commit/f8d1de600bc66f02827789b5baed3c35abbd2d27))
 - **REFACTOR**: Uptick min dart version ([#139](https://github.com/conduit-dart/conduit/issues/139)). ([45723b81](https://github.com/conduit-dart/conduit/commit/45723b81f99259998dac08e1db3f5f8aa64f80dd))
 - **REFACTOR**: Run analyzer and fix lint issues, possible perf improvements ([#128](https://github.com/conduit-dart/conduit/issues/128)). ([0675a4eb](https://github.com/conduit-dart/conduit/commit/0675a4ebe0e9e7574fed73c753f753d82c378cb9))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: Upgrade to latest dependencies ([#120](https://github.com/conduit-dart/conduit/issues/120)). ([2be7f7aa](https://github.com/conduit-dart/conduit/commit/2be7f7aa6fb8085cd21956fead60dc8d10f5daf2))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **FEAT**: Works with latest version of dart (2.19), CI works, websockets fixed, melos tasks added:wq. ([616a99be](https://github.com/conduit-dart/conduit/commit/616a99be9624b34c0a01acd7ff4a67b0d8b9a75f))
 - **DOCS**: improve doc gen ([#180](https://github.com/conduit-dart/conduit/issues/180)). ([8d18f872](https://github.com/conduit-dart/conduit/commit/8d18f872fa70ceec3052077c0e6adbc6c7ac6953))
 - **DOCS**: Add doc generation and housekeeping ([#156](https://github.com/conduit-dart/conduit/issues/156)). ([89f303c8](https://github.com/conduit-dart/conduit/commit/89f303c88251ec2228e58d807fc553839c3c967d))

#### `conduit_common` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **REFACTOR**: Limit ci runs and uptick lint package ([#160](https://github.com/conduit-dart/conduit/issues/160)). ([f8d1de60](https://github.com/conduit-dart/conduit/commit/f8d1de600bc66f02827789b5baed3c35abbd2d27))
 - **REFACTOR**: Uptick min dart version ([#139](https://github.com/conduit-dart/conduit/issues/139)). ([45723b81](https://github.com/conduit-dart/conduit/commit/45723b81f99259998dac08e1db3f5f8aa64f80dd))
 - **REFACTOR**: Apply standard lint analysis, refactor some nullables ([#129](https://github.com/conduit-dart/conduit/issues/129)). ([17f71bbb](https://github.com/conduit-dart/conduit/commit/17f71bbbe32cdb69947b6175f4ea46941be20410))
 - **REFACTOR**: Analyzer changes and publishing ([#127](https://github.com/conduit-dart/conduit/issues/127)). ([034ceb59](https://github.com/conduit-dart/conduit/commit/034ceb59542250553ff26695d1f8f10b0f3fd31b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: Handle private class in isolate ([#152](https://github.com/conduit-dart/conduit/issues/152)). ([28b87457](https://github.com/conduit-dart/conduit/commit/28b87457498242e353301ebbde00c858dd265482))
 - **FIX**(cli): Fix build binary command ([#121](https://github.com/conduit-dart/conduit/issues/121)). ([daba4b13](https://github.com/conduit-dart/conduit/commit/daba4b139558f429190acd530d76395bbe0e2405))
 - **FIX**: Upgrade to latest dependencies ([#120](https://github.com/conduit-dart/conduit/issues/120)). ([2be7f7aa](https://github.com/conduit-dart/conduit/commit/2be7f7aa6fb8085cd21956fead60dc8d10f5daf2))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **FEAT**: Works with latest version of dart (2.19), CI works, websockets fixed, melos tasks added:wq. ([616a99be](https://github.com/conduit-dart/conduit/commit/616a99be9624b34c0a01acd7ff4a67b0d8b9a75f))
 - **DOCS**: Sort out licensing and contributors ([#134](https://github.com/conduit-dart/conduit/issues/134)). ([1216ecf7](https://github.com/conduit-dart/conduit/commit/1216ecf7f83526004594634dddcf1df02d565a70))

#### `conduit_config` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **REFACTOR**: Limit ci runs and uptick lint package ([#160](https://github.com/conduit-dart/conduit/issues/160)). ([f8d1de60](https://github.com/conduit-dart/conduit/commit/f8d1de600bc66f02827789b5baed3c35abbd2d27))
 - **REFACTOR**: Uptick min dart version ([#139](https://github.com/conduit-dart/conduit/issues/139)). ([45723b81](https://github.com/conduit-dart/conduit/commit/45723b81f99259998dac08e1db3f5f8aa64f80dd))
 - **REFACTOR**: Apply standard lint analysis, refactor some nullables ([#129](https://github.com/conduit-dart/conduit/issues/129)). ([17f71bbb](https://github.com/conduit-dart/conduit/commit/17f71bbbe32cdb69947b6175f4ea46941be20410))
 - **REFACTOR**: Analyzer changes and publishing ([#127](https://github.com/conduit-dart/conduit/issues/127)). ([034ceb59](https://github.com/conduit-dart/conduit/commit/034ceb59542250553ff26695d1f8f10b0f3fd31b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: Handle private class in isolate ([#152](https://github.com/conduit-dart/conduit/issues/152)). ([28b87457](https://github.com/conduit-dart/conduit/commit/28b87457498242e353301ebbde00c858dd265482))
 - **FIX**(cli): Fix build binary command ([#121](https://github.com/conduit-dart/conduit/issues/121)). ([daba4b13](https://github.com/conduit-dart/conduit/commit/daba4b139558f429190acd530d76395bbe0e2405))
 - **FIX**: Upgrade to latest dependencies ([#120](https://github.com/conduit-dart/conduit/issues/120)). ([2be7f7aa](https://github.com/conduit-dart/conduit/commit/2be7f7aa6fb8085cd21956fead60dc8d10f5daf2))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **FEAT**: Works with latest version of dart (2.19), CI works, websockets fixed, melos tasks added:wq. ([616a99be](https://github.com/conduit-dart/conduit/commit/616a99be9624b34c0a01acd7ff4a67b0d8b9a75f))
 - **DOCS**: improve doc gen ([#180](https://github.com/conduit-dart/conduit/issues/180)). ([8d18f872](https://github.com/conduit-dart/conduit/commit/8d18f872fa70ceec3052077c0e6adbc6c7ac6953))
 - **DOCS**: Add doc generation and housekeeping ([#156](https://github.com/conduit-dart/conduit/issues/156)). ([89f303c8](https://github.com/conduit-dart/conduit/commit/89f303c88251ec2228e58d807fc553839c3c967d))

#### `conduit_core` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: Remove common test. ([cebcc417](https://github.com/conduit-dart/conduit/commit/cebcc417fc2849f18b7e9a2a1bbab412eda621ff))
 - **REFACTOR**: Remove pub_cache ([#188](https://github.com/conduit-dart/conduit/issues/188)). ([6d5beca1](https://github.com/conduit-dart/conduit/commit/6d5beca119fceaa7938402f171fc8983678c40b3))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([6f986c5f](https://github.com/conduit-dart/conduit/commit/6f986c5f875bfa7eb633a68394b546605da3dd9b))
 - **FIX**(ci): trigger. ([6239d395](https://github.com/conduit-dart/conduit/commit/6239d395098538e1c0484c704d534c6b41d92207))
 - **FIX**(ci): trigger. ([33c0f1ab](https://github.com/conduit-dart/conduit/commit/33c0f1ab4fe88945488758a576bd0986ee7af6f2))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: Attach finalizer on commit ([#186](https://github.com/conduit-dart/conduit/issues/186)). ([8408280e](https://github.com/conduit-dart/conduit/commit/8408280e23c5982e80d210034468b4ab5214a368))
 - **FIX**: core docs. ([1470ee70](https://github.com/conduit-dart/conduit/commit/1470ee70940fe6c4bbd4ba6d498eaed826297f51))
 - **FIX**: Check cli integrity ([#164](https://github.com/conduit-dart/conduit/issues/164)). ([5fd4e403](https://github.com/conduit-dart/conduit/commit/5fd4e4036d7316c91c2bfac3a06a2526096a9fac))
 - **FEAT**: sort predicate ([#203](https://github.com/conduit-dart/conduit/issues/203)). ([1f51879c](https://github.com/conduit-dart/conduit/commit/1f51879c26a37e4671206a79b2f319629173f046))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Replace ServiceRegistry with Finalizers ([#185](https://github.com/conduit-dart/conduit/issues/185)). ([73208e92](https://github.com/conduit-dart/conduit/commit/73208e92ceed79369405933b20d98c9ed48ed0e5))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **DOCS**: improve doc gen ([#180](https://github.com/conduit-dart/conduit/issues/180)). ([8d18f872](https://github.com/conduit-dart/conduit/commit/8d18f872fa70ceec3052077c0e6adbc6c7ac6953))

#### `conduit_isolate_exec` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **REFACTOR**: Limit ci runs and uptick lint package ([#160](https://github.com/conduit-dart/conduit/issues/160)). ([f8d1de60](https://github.com/conduit-dart/conduit/commit/f8d1de600bc66f02827789b5baed3c35abbd2d27))
 - **REFACTOR**: Uptick min dart version ([#139](https://github.com/conduit-dart/conduit/issues/139)). ([45723b81](https://github.com/conduit-dart/conduit/commit/45723b81f99259998dac08e1db3f5f8aa64f80dd))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: Upgrade to latest dependencies ([#120](https://github.com/conduit-dart/conduit/issues/120)). ([2be7f7aa](https://github.com/conduit-dart/conduit/commit/2be7f7aa6fb8085cd21956fead60dc8d10f5daf2))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **FEAT**: Works with latest version of dart (2.19), CI works, websockets fixed, melos tasks added:wq. ([616a99be](https://github.com/conduit-dart/conduit/commit/616a99be9624b34c0a01acd7ff4a67b0d8b9a75f))
 - **DOCS**: improve doc gen ([#180](https://github.com/conduit-dart/conduit/issues/180)). ([8d18f872](https://github.com/conduit-dart/conduit/commit/8d18f872fa70ceec3052077c0e6adbc6c7ac6953))
 - **DOCS**: Add doc generation and housekeeping ([#156](https://github.com/conduit-dart/conduit/issues/156)). ([89f303c8](https://github.com/conduit-dart/conduit/commit/89f303c88251ec2228e58d807fc553839c3c967d))

#### `conduit_open_api` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **REFACTOR**: Limit ci runs and uptick lint package ([#160](https://github.com/conduit-dart/conduit/issues/160)). ([f8d1de60](https://github.com/conduit-dart/conduit/commit/f8d1de600bc66f02827789b5baed3c35abbd2d27))
 - **REFACTOR**: Uptick min dart version ([#139](https://github.com/conduit-dart/conduit/issues/139)). ([45723b81](https://github.com/conduit-dart/conduit/commit/45723b81f99259998dac08e1db3f5f8aa64f80dd))
 - **REFACTOR**: Apply standard lint analysis, refactor some nullables ([#129](https://github.com/conduit-dart/conduit/issues/129)). ([17f71bbb](https://github.com/conduit-dart/conduit/commit/17f71bbbe32cdb69947b6175f4ea46941be20410))
 - **REFACTOR**: Run analyzer and fix lint issues, possible perf improvements ([#128](https://github.com/conduit-dart/conduit/issues/128)). ([0675a4eb](https://github.com/conduit-dart/conduit/commit/0675a4ebe0e9e7574fed73c753f753d82c378cb9))
 - **REFACTOR**: Analyzer changes and publishing ([#127](https://github.com/conduit-dart/conduit/issues/127)). ([034ceb59](https://github.com/conduit-dart/conduit/commit/034ceb59542250553ff26695d1f8f10b0f3fd31b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: Handle private class in isolate ([#152](https://github.com/conduit-dart/conduit/issues/152)). ([28b87457](https://github.com/conduit-dart/conduit/commit/28b87457498242e353301ebbde00c858dd265482))
 - **FIX**(cli): Fix build binary command ([#121](https://github.com/conduit-dart/conduit/issues/121)). ([daba4b13](https://github.com/conduit-dart/conduit/commit/daba4b139558f429190acd530d76395bbe0e2405))
 - **FIX**: Upgrade to latest dependencies ([#120](https://github.com/conduit-dart/conduit/issues/120)). ([2be7f7aa](https://github.com/conduit-dart/conduit/commit/2be7f7aa6fb8085cd21956fead60dc8d10f5daf2))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **FEAT**: Works with latest version of dart (2.19), CI works, websockets fixed, melos tasks added:wq. ([616a99be](https://github.com/conduit-dart/conduit/commit/616a99be9624b34c0a01acd7ff4a67b0d8b9a75f))
 - **DOCS**: improve doc gen ([#180](https://github.com/conduit-dart/conduit/issues/180)). ([8d18f872](https://github.com/conduit-dart/conduit/commit/8d18f872fa70ceec3052077c0e6adbc6c7ac6953))
 - **DOCS**: Add doc generation and housekeeping ([#156](https://github.com/conduit-dart/conduit/issues/156)). ([89f303c8](https://github.com/conduit-dart/conduit/commit/89f303c88251ec2228e58d807fc553839c3c967d))

#### `conduit_password_hash` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **REFACTOR**: Limit ci runs and uptick lint package ([#160](https://github.com/conduit-dart/conduit/issues/160)). ([f8d1de60](https://github.com/conduit-dart/conduit/commit/f8d1de600bc66f02827789b5baed3c35abbd2d27))
 - **REFACTOR**: Uptick min dart version ([#139](https://github.com/conduit-dart/conduit/issues/139)). ([45723b81](https://github.com/conduit-dart/conduit/commit/45723b81f99259998dac08e1db3f5f8aa64f80dd))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: Upgrade to latest dependencies ([#120](https://github.com/conduit-dart/conduit/issues/120)). ([2be7f7aa](https://github.com/conduit-dart/conduit/commit/2be7f7aa6fb8085cd21956fead60dc8d10f5daf2))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **FEAT**: Works with latest version of dart (2.19), CI works, websockets fixed, melos tasks added:wq. ([616a99be](https://github.com/conduit-dart/conduit/commit/616a99be9624b34c0a01acd7ff4a67b0d8b9a75f))
 - **DOCS**: improve doc gen ([#180](https://github.com/conduit-dart/conduit/issues/180)). ([8d18f872](https://github.com/conduit-dart/conduit/commit/8d18f872fa70ceec3052077c0e6adbc6c7ac6953))
 - **DOCS**: Add doc generation and housekeeping ([#156](https://github.com/conduit-dart/conduit/issues/156)). ([89f303c8](https://github.com/conduit-dart/conduit/commit/89f303c88251ec2228e58d807fc553839c3c967d))

#### `conduit_postgresql` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **REFACTOR**: Remove common test. ([cebcc417](https://github.com/conduit-dart/conduit/commit/cebcc417fc2849f18b7e9a2a1bbab412eda621ff))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([df30ab5c](https://github.com/conduit-dart/conduit/commit/df30ab5c6a7c0855d8572f67d3cdede6f7efe0f8))
 - **FIX**(ci): trigger. ([6f986c5f](https://github.com/conduit-dart/conduit/commit/6f986c5f875bfa7eb633a68394b546605da3dd9b))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FEAT**: sort predicate ([#203](https://github.com/conduit-dart/conduit/issues/203)). ([1f51879c](https://github.com/conduit-dart/conduit/commit/1f51879c26a37e4671206a79b2f319629173f046))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))

#### `fs_test_agent` - `v5.0.3`

 - **REFACTOR**: ci and code quality ([#222](https://github.com/conduit-dart/conduit/issues/222)). ([d6e60631](https://github.com/conduit-dart/conduit/commit/d6e606315f55e851b80237984cd6082c4abfbdc2))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **REFACTOR**: Bump min required dart version ([#187](https://github.com/conduit-dart/conduit/issues/187)). ([0e870402](https://github.com/conduit-dart/conduit/commit/0e8704028d55d2e924aa72fa8e5e72711c8f4a07))
 - **REFACTOR**: Limit ci runs and uptick lint package ([#160](https://github.com/conduit-dart/conduit/issues/160)). ([f8d1de60](https://github.com/conduit-dart/conduit/commit/f8d1de600bc66f02827789b5baed3c35abbd2d27))
 - **REFACTOR**: Uptick min dart version ([#139](https://github.com/conduit-dart/conduit/issues/139)). ([45723b81](https://github.com/conduit-dart/conduit/commit/45723b81f99259998dac08e1db3f5f8aa64f80dd))
 - **REFACTOR**: Run analyzer and fix lint issues, possible perf improvements ([#128](https://github.com/conduit-dart/conduit/issues/128)). ([0675a4eb](https://github.com/conduit-dart/conduit/commit/0675a4ebe0e9e7574fed73c753f753d82c378cb9))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FIX**(ci): trigger. ([36e63b05](https://github.com/conduit-dart/conduit/commit/36e63b05bd5b21c858cdf52808b195323b931d4a))
 - **FIX**(ci): test publish CI. ([7444f6ed](https://github.com/conduit-dart/conduit/commit/7444f6ed7042bfab50ce6bc285fa16530c69d34d))
 - **FIX**: remove common_test from core. ([94867de3](https://github.com/conduit-dart/conduit/commit/94867de38d11d020895fbf984fbac7167db928e1))
 - **FIX**: Versioning issues and upkeep ([#191](https://github.com/conduit-dart/conduit/issues/191)). ([faa916ba](https://github.com/conduit-dart/conduit/commit/faa916ba6fe25ce3d3ce3878b8508741e611e2af))
 - **FIX**: Upgrade to latest dependencies ([#120](https://github.com/conduit-dart/conduit/issues/120)). ([2be7f7aa](https://github.com/conduit-dart/conduit/commit/2be7f7aa6fb8085cd21956fead60dc8d10f5daf2))
 - **FEAT**: Prepping for orm ([#190](https://github.com/conduit-dart/conduit/issues/190)). ([e82dfa6f](https://github.com/conduit-dart/conduit/commit/e82dfa6f6fc70a3a41f7e832fbf787a15343266d))
 - **FEAT**: Separates core framework and cli ([#161](https://github.com/conduit-dart/conduit/issues/161)). ([28445bbe](https://github.com/conduit-dart/conduit/commit/28445bbe2c012a3a16d372f6ddf29d344939e72f))
 - **FEAT**: Works with latest version of dart (2.19), CI works, websockets fixed, melos tasks added:wq. ([616a99be](https://github.com/conduit-dart/conduit/commit/616a99be9624b34c0a01acd7ff4a67b0d8b9a75f))
 - **DOCS**: improve doc gen ([#180](https://github.com/conduit-dart/conduit/issues/180)). ([8d18f872](https://github.com/conduit-dart/conduit/commit/8d18f872fa70ceec3052077c0e6adbc6c7ac6953))
 - **DOCS**: Add doc generation and housekeeping ([#156](https://github.com/conduit-dart/conduit/issues/156)). ([89f303c8](https://github.com/conduit-dart/conduit/commit/89f303c88251ec2228e58d807fc553839c3c967d))


## 2024-02-28

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`conduit` - `v5.0.1`](#conduit---v501)
 - [`conduit_codable` - `v5.0.1`](#conduit_codable---v501)
 - [`conduit_common` - `v5.0.1`](#conduit_common---v501)
 - [`conduit_config` - `v5.0.1`](#conduit_config---v501)
 - [`conduit_core` - `v5.0.1`](#conduit_core---v501)
 - [`conduit_isolate_exec` - `v5.0.1`](#conduit_isolate_exec---v501)
 - [`conduit_open_api` - `v5.0.1`](#conduit_open_api---v501)
 - [`conduit_password_hash` - `v5.0.1`](#conduit_password_hash---v501)
 - [`conduit_postgresql` - `v5.0.1`](#conduit_postgresql---v501)
 - [`conduit_runtime` - `v5.0.1`](#conduit_runtime---v501)
 - [`conduit_test` - `v5.0.1`](#conduit_test---v501)
 - [`fs_test_agent` - `v5.0.1`](#fs_test_agent---v501)

---

#### `conduit` - `v5.0.1`

 - Bump "conduit" to `5.0.1`.

#### `conduit_codable` - `v5.0.1`

 - Bump "conduit_codable" to `5.0.1`.

#### `conduit_common` - `v5.0.1`

 - Bump "conduit_common" to `5.0.1`.

#### `conduit_config` - `v5.0.1`

 - Bump "conduit_config" to `5.0.1`.

#### `conduit_core` - `v5.0.1`

 - Bump "conduit_core" to `5.0.1`.

#### `conduit_isolate_exec` - `v5.0.1`

 - Bump "conduit_isolate_exec" to `5.0.1`.

#### `conduit_open_api` - `v5.0.1`

 - Bump "conduit_open_api" to `5.0.1`.

#### `conduit_password_hash` - `v5.0.1`

 - Bump "conduit_password_hash" to `5.0.1`.

#### `conduit_postgresql` - `v5.0.1`

 - Bump "conduit_postgresql" to `5.0.1`.

#### `conduit_runtime` - `v5.0.1`

 - Bump "conduit_runtime" to `5.0.1`.

#### `conduit_test` - `v5.0.1`

 - Bump "conduit_test" to `5.0.1`.

#### `fs_test_agent` - `v5.0.1`

 - Bump "fs_test_agent" to `5.0.1`.


## 2024-02-27

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`conduit` - `v5.0.0`](#conduit---v500)
 - [`conduit_codable` - `v5.0.0`](#conduit_codable---v500)
 - [`conduit_common` - `v5.0.0`](#conduit_common---v500)
 - [`conduit_config` - `v5.0.0`](#conduit_config---v500)
 - [`conduit_core` - `v5.0.0`](#conduit_core---v500)
 - [`conduit_isolate_exec` - `v5.0.0`](#conduit_isolate_exec---v500)
 - [`conduit_open_api` - `v5.0.0`](#conduit_open_api---v500)
 - [`conduit_password_hash` - `v5.0.0`](#conduit_password_hash---v500)
 - [`conduit_postgresql` - `v5.0.0`](#conduit_postgresql---v500)
 - [`conduit_runtime` - `v5.0.0`](#conduit_runtime---v500)
 - [`conduit_test` - `v5.0.0`](#conduit_test---v500)
 - [`fs_test_agent` - `v5.0.0`](#fs_test_agent---v500)

---

#### `conduit` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**: housekeeping dart version uptick. ([826f2805](https://github.com/conduit-dart/conduit/commit/826f2805666af5903ad868a7c9715cf90d2a000e))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))

#### `conduit_codable` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))

#### `conduit_common` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))

#### `conduit_config` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))

#### `conduit_core` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **FIX**(ci): Publish automation fix ([#217](https://github.com/conduit-dart/conduit/issues/217)). ([2da2db05](https://github.com/conduit-dart/conduit/commit/2da2db058feb8f8bb6c0b97a8144252c188765c8))

#### `conduit_isolate_exec` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))

#### `conduit_open_api` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))

#### `conduit_password_hash` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))

#### `conduit_postgresql` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))

#### `conduit_runtime` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))

#### `conduit_test` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))

#### `fs_test_agent` - `v5.0.0`

 - **REFACTOR**: housekeeping 2 20 24 ([#216](https://github.com/conduit-dart/conduit/issues/216)). ([5fd4d59b](https://github.com/conduit-dart/conduit/commit/5fd4d59bd1e20485f7af4871995a689e910a969d))
 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))


## 2023-11-22

### Changes

---

Packages with breaking changes:

 - [`conduit` - `v4.4.0`](#conduit---v4310)
 - [`conduit_codable` - `v4.3.8`](#conduit_codable---v438)
 - [`conduit_common` - `v4.3.8`](#conduit_common---v438)
 - [`conduit_config` - `v4.3.8`](#conduit_config---v438)
 - [`conduit_isolate_exec` - `v4.3.8`](#conduit_isolate_exec---v438)
 - [`conduit_open_api` - `v4.3.8`](#conduit_open_api---v438)
 - [`conduit_password_hash` - `v4.3.8`](#conduit_password_hash---v438)
 - [`conduit_runtime` - `v4.3.8`](#conduit_runtime---v438)
 - [`conduit_test` - `v4.3.8`](#conduit_test---v438)
 - [`fs_test_agent` - `v4.3.8`](#fs_test_agent---v438)

Packages with other changes:

 - [`conduit_core` - `v4.4.0`](#conduit_core---v440)
 - [`conduit_postgresql` - `v4.4.0`](#conduit_postgresql---v440)

Packages graduated to a stable release (see pre-releases prior to the stable version for changelog entries):

 - `conduit` - `v4.4.0`
 - `conduit_codable` - `v4.3.8`
 - `conduit_common` - `v4.3.8`
 - `conduit_config` - `v4.3.8`
 - `conduit_core` - `v4.4.0`
 - `conduit_isolate_exec` - `v4.3.8`
 - `conduit_open_api` - `v4.3.8`
 - `conduit_password_hash` - `v4.3.8`
 - `conduit_postgresql` - `v4.4.0`
 - `conduit_runtime` - `v4.3.8`
 - `conduit_test` - `v4.3.8`
 - `fs_test_agent` - `v4.3.8`

---

#### `conduit` - `v4.4.0`

#### `conduit_codable` - `v4.3.8`

#### `conduit_common` - `v4.3.8`

#### `conduit_config` - `v4.3.8`

#### `conduit_isolate_exec` - `v4.3.8`

#### `conduit_open_api` - `v4.3.8`

#### `conduit_password_hash` - `v4.3.8`

#### `conduit_runtime` - `v4.3.8`

#### `conduit_test` - `v4.3.8`

#### `fs_test_agent` - `v4.3.8`

#### `conduit_core` - `v4.4.0`

#### `conduit_postgresql` - `v4.4.0`


## 2023-11-22

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`conduit` - `v4.4.0-dev.0`](#conduit---v4310-dev0)
 - [`conduit_codable` - `v4.3.8-dev.0`](#conduit_codable---v438-dev0)
 - [`conduit_common` - `v4.3.8-dev.0`](#conduit_common---v438-dev0)
 - [`conduit_config` - `v4.3.8-dev.0`](#conduit_config---v438-dev0)
 - [`conduit_core` - `v4.4.0-dev.0`](#conduit_core---v440-dev0)
 - [`conduit_isolate_exec` - `v4.3.8-dev.0`](#conduit_isolate_exec---v438-dev0)
 - [`conduit_open_api` - `v4.3.8-dev.0`](#conduit_open_api---v438-dev0)
 - [`conduit_password_hash` - `v4.3.8-dev.0`](#conduit_password_hash---v438-dev0)
 - [`conduit_postgresql` - `v4.4.0-dev.0`](#conduit_postgresql---v440-dev0)
 - [`conduit_runtime` - `v4.3.8-dev.0`](#conduit_runtime---v438-dev0)
 - [`conduit_test` - `v4.3.8-dev.0`](#conduit_test---v438-dev0)
 - [`fs_test_agent` - `v4.3.8-dev.0`](#fs_test_agent---v438-dev0)

---

#### `conduit` - `v4.4.0-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))

#### `conduit_codable` - `v4.3.8-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))

#### `conduit_common` - `v4.3.8-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))

#### `conduit_config` - `v4.3.8-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))

#### `conduit_core` - `v4.4.0-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FEAT**: sort predicate ([#203](https://github.com/conduit-dart/conduit/issues/203)). ([1f51879c](https://github.com/conduit-dart/conduit/commit/1f51879c26a37e4671206a79b2f319629173f046))

#### `conduit_isolate_exec` - `v4.3.8-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))

#### `conduit_open_api` - `v4.3.8-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))

#### `conduit_password_hash` - `v4.3.8-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))

#### `conduit_postgresql` - `v4.4.0-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))
 - **FEAT**: sort predicate ([#203](https://github.com/conduit-dart/conduit/issues/203)). ([1f51879c](https://github.com/conduit-dart/conduit/commit/1f51879c26a37e4671206a79b2f319629173f046))

#### `conduit_runtime` - `v4.3.8-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))

#### `conduit_test` - `v4.3.8-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))

#### `fs_test_agent` - `v4.3.8-dev.0`

 - **REFACTOR**(postgres): BREAKING CHANGE major release for postgres driver. ([d6bf1165](https://github.com/conduit-dart/conduit/commit/d6bf1165f6903cb133b1ec4bf3d66242646f548b))
 - **REFACTOR**: House Keeping July 22. ([cf1eb45e](https://github.com/conduit-dart/conduit/commit/cf1eb45e035a202a97c6baab3348c030a667628b))
 - **FIX**: Melos stuff ([#199](https://github.com/conduit-dart/conduit/issues/199)). ([20bc466d](https://github.com/conduit-dart/conduit/commit/20bc466daea0f82019aaf4c04edeab64a83038f9))

