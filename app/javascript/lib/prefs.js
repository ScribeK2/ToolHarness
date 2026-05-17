const PREFIX = "th."

export const Prefs = {
  get(key, fallback = null) {
    try {
      const raw = localStorage.getItem(PREFIX + key)
      return raw === null ? fallback : JSON.parse(raw)
    } catch (_) {
      return fallback
    }
  },

  set(key, value) {
    try {
      localStorage.setItem(PREFIX + key, JSON.stringify(value))
    } catch (_) {}
  },

  remove(key) {
    try {
      localStorage.removeItem(PREFIX + key)
    } catch (_) {}
  }
}
