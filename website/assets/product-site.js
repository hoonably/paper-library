document.querySelectorAll('[data-feature-gallery]').forEach(gallery => {
  const tabs = [...gallery.querySelectorAll('[role="tab"]')];
  const panels = [...gallery.querySelectorAll('[role="tabpanel"]')];
  const select = index => {
    tabs.forEach((tab, i) => {
      const active = i === index;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
      panels[i].hidden = !active;
      if (active) {
        const image = panels[i].querySelector('img');
        if (image) image.loading = 'eager';
      }
    });
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => select(index));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (index + 1) % tabs.length;
      else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (index + tabs.length - 1) % tabs.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tabs.length - 1;
      else return;
      event.preventDefault();
      select(next);
      tabs[next].focus();
    });
  });
});

const imageDialog = document.querySelector('.image-dialog');
if (imageDialog) {
  let opener;
  const image = imageDialog.querySelector('img');
  const fitImage = () => {
    if (!image.naturalWidth) return;
    const scale = window.devicePixelRatio || 1;
    image.style.maxWidth = `min(1200px, 94vw, ${image.naturalWidth / scale}px)`;
    image.style.maxHeight = `min(92dvh, ${image.naturalHeight / scale}px)`;
  };
  image.addEventListener('load', fitImage);
  window.addEventListener('resize', () => { if (imageDialog.open) fitImage(); });
  document.querySelectorAll('[data-image]').forEach(button => button.addEventListener('click', () => {
    opener = button;
    image.src = button.dataset.image;
    image.alt = button.querySelector('img').alt;
    fitImage();
    imageDialog.showModal();
  }));
  imageDialog.querySelector('button').addEventListener('click', () => imageDialog.close());
  imageDialog.addEventListener('close', () => opener?.focus({ preventScroll: true }));
  imageDialog.addEventListener('click', event => {
    if (event.target !== imageDialog) return;
    const r = imageDialog.getBoundingClientRect();
    if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) imageDialog.close();
  });
}
