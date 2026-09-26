package io.github.rodrigofabreu.signalhub;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/** How a build names its release: the version and commit the release baked in, or neither. */
class BuildInfoTest {

  @Test
  void releaseBuildReportsItsVersionAndCommit() {
    var info = new BuildInfo(Optional.of("1.2.3"), Optional.of("0123456789abcdef"));

    assertEquals("1.2.3", info.version());
    assertEquals(Optional.of("0123456789abcdef"), info.revision());
    assertEquals("SignalHub 1.2.3 (commit 0123456789abcdef)", info.describe());
    assertEquals(Map.of("version", "1.2.3", "revision", "0123456789abcdef"), info.data());
  }

  @Test
  void buildWithoutAVersionIsADevelopmentBuild() {
    var info = new BuildInfo(Optional.empty(), Optional.empty());

    assertEquals("development", info.version());
    assertEquals(Optional.empty(), info.revision());
    assertEquals("SignalHub development build", info.describe());
    assertEquals(Map.of("version", "development"), info.data());
  }

  @Test
  void blankValuesCountAsMissing() {
    // An image built without the release's build arguments sets both variables to "".
    var info = new BuildInfo(Optional.of(" "), Optional.of(""));

    assertEquals("SignalHub development build", info.describe());
    assertEquals(Map.of("version", "development"), info.data());
  }

  @Test
  void developmentBuildKeepsARecordedCommit() {
    var info = new BuildInfo(Optional.empty(), Optional.of("0123456789abcdef"));

    assertEquals("SignalHub development build (commit 0123456789abcdef)", info.describe());
    assertEquals(Map.of("version", "development", "revision", "0123456789abcdef"), info.data());
  }
}
