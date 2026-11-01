// Start with the full list of titles when the expanded paper would push it below the fold.
const paperCover = document.querySelector('.paper-cover');
if (paperCover.getBoundingClientRect().bottom + window.scrollY > document.documentElement.clientHeight + 1) {
  paperCover.querySelector('.paper-record[open]')?.removeAttribute('open');
}
