package io.github.rodrigofabreu.signalhub.client;

/**
 * Names a browser from its {@code User-Agent} for people to recognise in a list ("Firefox on
 * Linux"). Only a label: it is never used to decide anything, and a browser may say what it likes.
 */
final class BrowserNames {

  static final String UNKNOWN = "Browser";

  private BrowserNames() {}

  static String of(String userAgent) {
    if (userAgent == null || userAgent.isBlank()) {
      return UNKNOWN;
    }
    var browser = browser(userAgent);
    var system = system(userAgent);
    if (browser == null) {
      return system == null ? UNKNOWN : UNKNOWN + " on " + system;
    }
    return system == null ? browser : browser + " on " + system;
  }

  // Order matters: Edge and Opera also say Chrome, and Chrome also says Safari.
  private static String browser(String ua) {
    if (ua.contains("Edg/") || ua.contains("EdgA/") || ua.contains("EdgiOS/")) {
      return "Edge";
    }
    if (ua.contains("OPR/") || ua.contains("Opera")) {
      return "Opera";
    }
    if (ua.contains("Firefox/") || ua.contains("FxiOS/")) {
      return "Firefox";
    }
    if (ua.contains("Chrome/") || ua.contains("CriOS/")) {
      return "Chrome";
    }
    if (ua.contains("Safari/")) {
      return "Safari";
    }
    return null;
  }

  // iPhone and iPad first: their agents also say "like Mac OS X". Android also says Linux.
  private static String system(String ua) {
    if (ua.contains("iPhone")) {
      return "iPhone";
    }
    if (ua.contains("iPad")) {
      return "iPad";
    }
    if (ua.contains("Android")) {
      return "Android";
    }
    if (ua.contains("Windows")) {
      return "Windows";
    }
    if (ua.contains("Mac OS X") || ua.contains("Macintosh")) {
      return "macOS";
    }
    if (ua.contains("CrOS")) {
      return "ChromeOS";
    }
    if (ua.contains("Linux") || ua.contains("X11")) {
      return "Linux";
    }
    return null;
  }
}
