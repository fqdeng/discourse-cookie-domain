import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("1.13.0", (api) => {
  const PREFIX = "plugin_redirect_url=";

  const readDestinationUrl = () => {
    const raw = document.cookie
      .split(";")
      .map((c) => c.trim())
      .find((c) => c.startsWith(PREFIX));
    if (!raw) return null;
    try {
      return decodeURIComponent(raw.substring(PREFIX.length).replace(/\+/g, "%20"));
    } catch (e) {
      return null;
    }
  };

  const clearDestinationUrl = () => {
    document.cookie = "plugin_redirect_url=; Path=/; Max-Age=0";
  };

  api.onPageChange(() => {
    if (!api.getCurrentUser()) return;

    const destination = readDestinationUrl();
    if (!destination) return;
    if (!/^https?:\/\//i.test(destination)) return;

    clearDestinationUrl();
    window.location.replace(destination);
  });
});
