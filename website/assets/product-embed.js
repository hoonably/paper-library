// Only the cover's public height crosses the iframe boundary.
if (window.parent !== window) {
  const cover = document.querySelector("main");
  const reportHeight = () => {
    const height = Math.ceil(cover.getBoundingClientRect().height);
    if (height > 0) window.parent.postMessage({ type: "product-cover:height", height }, "*");
  };
  new ResizeObserver(reportHeight).observe(cover);
  window.addEventListener("message", event => {
    if (event.source === window.parent && event.data === "product-cover:measure") reportHeight();
  });
}
