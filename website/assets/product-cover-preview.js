async function loadProductCover() {
  const response = await fetch("/", { cache: "no-cache" });
  if (!response.ok) throw new Error(`Product page returned ${response.status}`);

  const page = new DOMParser().parseFromString(await response.text(), "text/html");
  const cover = page.querySelector("main > .product-cover");
  if (!cover) throw new Error("Missing product cover");

  const stylesheets = [...page.head.querySelectorAll('link[rel="stylesheet"]')];
  const styled = stylesheets.map(link => new Promise(resolve => {
    link.addEventListener("load", resolve, { once: true });
    link.addEventListener("error", resolve, { once: true });
    document.head.append(link);
  }));

  document.body.className = page.body.className;
  document.querySelector("main").append(cover);
  const dialog = page.body.querySelector(".image-dialog");
  if (dialog) document.body.append(dialog);

  await Promise.all(styled);
  // The directory menu runs only on the full page. Cover interactions use assets/.
  for (const source of page.head.querySelectorAll('script[src^="assets/"]')) {
    const script = document.createElement("script");
    script.async = false;
    script.src = source.getAttribute("src");
    document.head.append(script);
  }
  const resize = document.createElement("script");
  resize.src = "assets/product-embed.js";
  document.head.append(resize);
}

loadProductCover().catch(error => console.error("Could not load the product cover", error));
