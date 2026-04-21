import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("1.13.0", (api) => {
  const PREFIX = "plugin_redirect_url=";
  const TAG = "[CookieDomainRedirect]";

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

  const maybeRedirect = (source) => {
    const user = api.getCurrentUser();
    const destination = readDestinationUrl();
    // eslint-disable-next-line no-console
    console.debug(TAG, source, {
      loggedIn: !!user,
      hasCookie: !!destination,
      destination,
      path: window.location.pathname,
    });

    if (!user) return;
    if (!destination) return;
    if (!/^https?:\/\//i.test(destination)) return;

    clearDestinationUrl();
    // eslint-disable-next-line no-console
    console.info(TAG, "redirecting to", destination);
    window.location.replace(destination);
  };

  maybeRedirect("init");
  api.onPageChange(() => maybeRedirect("pageChange"));
});
