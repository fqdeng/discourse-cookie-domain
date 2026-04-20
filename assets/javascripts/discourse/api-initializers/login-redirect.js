import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("1.13.0", (api) => {
  const readDestinationUrl = () => {
    const prefix = "destination_url=";
    const raw = document.cookie
      .split(";")
      .map((c) => c.trim())
      .find((c) => c.startsWith(prefix));
    if (!raw) return null;
    try {
      return decodeURIComponent(raw.substring(prefix.length).replace(/\+/g, "%20"));
    } catch (e) {
      return null;
    }
  };

  const clearDestinationUrl = () => {
    document.cookie = "destination_url=; Path=/; Max-Age=0";
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
