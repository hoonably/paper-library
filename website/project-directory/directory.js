/* Generated copies are self-contained. Edit shared/project-directory in jeonghoonpark.com. */
(() => {
  const projects = [{"id":"when2jam","name":"when2jam","kind":"Web","description":"각자의 시간에서 함께할 시간으로.","descriptionEn":"Find a time to get together.","siteUrl":"https://when2jam.pages.dev/","plannedUrl":"https://when2jam.pages.dev/","repository":"https://github.com/hoonably/when2jam","repositoryPublic":false,"previewUrl":"http://127.0.0.1:4171/","color":"#256b54","symbol":"calendar"},{"id":"cosmoss","name":"cosMOSS","kind":"macOS","description":"녹음에서 전사, 검토, 요약까지.","descriptionEn":"Turn recordings into useful notes.","siteUrl":"https://cosmoss.pages.dev/","plannedUrl":"https://cosmoss.pages.dev/","repository":"https://github.com/hoonably/cosMOSS","repositoryPublic":true,"previewUrl":"http://127.0.0.1:4173/","color":"#178054","symbol":"wave"},{"id":"pickly","name":"Pickly","kind":"macOS","description":"사진을 정리하고, 다시 찾기 쉽게.","descriptionEn":"Organize photos. Find your moments.","siteUrl":"https://pickly.pages.dev/","plannedUrl":"https://pickly.pages.dev/","repository":"https://github.com/hoonably/pickly","repositoryPublic":false,"previewUrl":"http://127.0.0.1:4174/","color":"#547c71","symbol":"photo"},{"id":"paper-library","name":"Paper Library","kind":"macOS","description":"논문을 읽고, 정리하고, 다시 찾는 곳.","descriptionEn":"Read, organize, and rediscover papers.","siteUrl":"https://paper-library.pages.dev/","plannedUrl":"https://paper-library.pages.dev/","repository":"https://github.com/hoonably/paper-library","repositoryPublic":true,"previewUrl":"http://127.0.0.1:4175/","color":"#687950","symbol":"paper"},{"id":"macro-studio","name":"Macro Studio","kind":"Chrome","description":"반복하는 웹 작업을 나만의 매크로로.","descriptionEn":"Make your own macros for repeat web tasks.","siteUrl":"https://macro-studio.pages.dev/","plannedUrl":"https://macro-studio.pages.dev/","repository":"https://github.com/hoonably/macro-studio","repositoryPublic":true,"previewUrl":"http://127.0.0.1:4176/","color":"#446bac","symbol":"macro"},{"id":"talk-zero","name":"Talk Zero","kind":"macOS","description":"광고는 비우고, 대화는 더 넓게.","descriptionEn":"Less ad space. More room for conversations.","siteUrl":"https://talk-zero.pages.dev/","plannedUrl":"https://talk-zero.pages.dev/","repository":"https://github.com/hoonably/talk-zero","repositoryPublic":false,"previewUrl":"http://127.0.0.1:4177/","color":"#92701d","symbol":"chat","iconSource":"talk-zero/macos/Resources/BrandIcon.svg","iconSvg":"<svg aria-hidden=\"true\" xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" fill=\"none\">\n  <title>Talk Zero</title>\n  <rect x=\"64\" y=\"64\" width=\"896\" height=\"896\" rx=\"236\" fill=\"#F5CC40\"/>\n  <path d=\"M599 345L347 345C297 345 257 385 257 435L257 565C257 615 297 655 347 655L355 655L355 741L463 655L631 655C681 655 721 615 721 565L721 462\" stroke=\"#302710\" stroke-width=\"36\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n  <path d=\"M721 266.25C728.5 318.75 746 337.5 798.5 345C746 352.5 728.5 371.25 721 423.75C713.5 371.25 696 352.5 643.5 345C696 337.5 713.5 318.75 721 266.25Z\" fill=\"#302710\"/>\n</svg>\n"}];
  const paths = {
    calendar: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4m10-4v4M3 11h18m-13 5 3 3 5-5"/>',
    wave: '<path d="M3 10v4m4-8v12m5-16v20m5-16v12m4-8v4"/>',
    photo: '<rect x="3" y="3" width="18" height="18" rx="4"/><circle cx="8" cy="8" r="1.5"/><path d="m3 17 6-6 4 4 3-3 5 5"/>',
    paper: '<path d="M7 3h8l4 4v14H5V3h2m8 0v5h4M8 12h8m-8 4h6"/>',
    macro: '<rect x="3" y="3" width="18" height="18" rx="4"/><path d="M8 8h8v8m-8 0 8-8"/>'
  };
  const icon = (project) => project.iconSvg || `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[project.symbol]}</svg>`;
  const target = (project) => project.siteUrl;
  class ProjectDirectory extends HTMLElement {
    connectedCallback() {
      if (this.shadowRoot) return;
      const root = this.attachShadow({ mode: 'open' });
      const english = this.getAttribute('lang') === 'en';
      root.innerHTML = `<style>
        :host{display:inline-block;font-family:inherit;line-height:1.5;color:inherit}
        *{box-sizing:border-box}button,a{-webkit-tap-highlight-color:transparent}button{font:inherit;cursor:pointer}a{text-decoration:none;color:inherit}
        .trigger{display:inline-flex;align-items:center;gap:9px;padding:10px 0;border:0;background:none;color:inherit;font-size:13px;font-weight:600}.trigger:hover{color:#256b54}.trigger svg{width:16px;height:16px}
        :host([placement="header"]) .trigger{gap:8px;padding:10px 14px;border:1px solid #dce5dc;border-radius:10px;background:#fff8;color:#334e40;font-weight:550;white-space:nowrap;transition:background .15s,border-color .15s}
        :host([placement="header"]) .trigger:hover{background:#edf4ee;border-color:#a4bba9}
        @media(max-width:540px){:host([placement="header"]) .trigger{padding:9px 11px;font-size:12px}}
        @media(max-width:380px){:host([placement="header"]) .trigger{width:40px;height:40px;justify-content:center;padding:0}:host([placement="header"]) .trigger-label{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}}
        button:focus-visible,a:focus-visible{outline:2px solid #256b54;outline-offset:4px}
        dialog{width:min(780px,calc(100vw - 32px));max-height:calc(100dvh - 48px);margin:auto;padding:32px;border:1px solid #dde6dc;border-radius:20px;background:#f8faf8;color:#243d32;box-shadow:0 24px 100px #102c2440;overscroll-behavior:contain}
        dialog::backdrop{background:#14271d80;backdrop-filter:blur(4px)}header{display:flex;align-items:flex-start;justify-content:space-between;gap:20px}.eyebrow{color:#587567;font-size:10px;letter-spacing:.14em;font-weight:650;margin:0 0 8px}h2{font-size:27px;letter-spacing:-1px;font-weight:650;margin:0}header p:last-child{color:#63766b;font-size:13px;margin:9px 0 25px}.close{flex:none;width:36px;height:36px;border:1px solid #dce5dc;border-radius:50%;background:#fff;color:#53685c;font-size:23px;line-height:1}
        .projects{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.project{display:grid;grid-template-columns:42px minmax(0,1fr) 15px;gap:13px;align-items:center;padding:20px 17px;border:1px solid #e0e7de;border-radius:12px;background:#fff;transition:border-color .15s,transform .15s}.project:hover{border-color:#9bb8a7;transform:translateY(-2px)}.mark{display:grid;place-items:center;width:42px;height:42px;border-radius:11px;background:color-mix(in srgb,var(--brand) 9%,white);color:var(--brand)}.mark svg{width:23px;height:23px}.mark.app-icon{background:transparent;border-radius:0}.mark.app-icon svg{width:100%;height:100%}strong{display:block;font-size:15px;letter-spacing:-.2px}.kind{font-size:10px;color:#718176;margin-bottom:3px}.description{display:block;font-size:11px;color:#64786b;margin-top:5px;line-height:1.6}.arrow{color:#7a8d80;font-size:16px}.project[aria-current=page]{border-color:#a0bba6;background:#f2f7f0}.current{font-size:10px;font-weight:500;color:#52775e;margin-left:6px}footer{border-top:1px solid #e1e8df;margin-top:22px;padding-top:17px;display:flex;justify-content:space-between;gap:12px;font-size:11px;color:#6b7e71}footer a:hover{text-decoration:underline}
        @media(max-width:560px){dialog{padding:23px 18px;border-radius:16px}.projects{grid-template-columns:1fr}.project{padding:16px}h2{font-size:24px}header p:last-child{margin-bottom:20px}}
        @media(prefers-reduced-motion:reduce){.project{transition:none}.project:hover{transform:none}}
      </style><button class="trigger" type="button" aria-haspopup="dialog"><span class="trigger-label">${english ? 'More projects' : '다른 프로젝트'}</span><svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true"><rect x="2" y="2" width="6" height="6" rx="1.3"/><rect x="12" y="2" width="6" height="6" rx="1.3"/><rect x="2" y="12" width="6" height="6" rx="1.3"/><rect x="12" y="12" width="6" height="6" rx="1.3"/></svg></button>
      <dialog aria-labelledby="directory-title"><header><div><p class="eyebrow">MADE BY JEONGHOON PARK</p><h2 id="directory-title">${english ? 'Small tools, useful every day.' : '일상에 조금 더 쓸모를.'}</h2><p>${english ? 'Tools for the way we work and spend time.' : '일상에서 쓰고, 직접 다듬는 도구들.'}</p></div><button class="close" type="button" aria-label="${english ? 'Close' : '닫기'}">×</button></header><nav class="projects" aria-label="${english ? 'Projects' : '프로젝트'}"></nav><footer><span>Web · Mac · Chrome</span><a href="https://jeonghoonpark.com/">Jeonghoon Park ↗</a></footer></dialog>`;
      const list = root.querySelector('.projects');
      for (const project of projects) {
        const link = document.createElement('a');
        link.className = 'project';
        link.href = target(project);
        link.style.setProperty('--brand', project.color);
        const current = project.id === this.getAttribute('current');
        if (current) link.setAttribute('aria-current', 'page');
        const mark = document.createElement('span'); mark.className = 'mark' + (project.iconSvg ? ' app-icon' : ''); mark.innerHTML = icon(project);
        const copy = document.createElement('span');
        const kind = document.createElement('span'); kind.className = 'kind'; kind.textContent = project.kind;
        const name = document.createElement('strong'); name.textContent = project.name;
        if (current) { const badge = document.createElement('span'); badge.className = 'current'; badge.textContent = english ? 'Here' : '현재'; name.append(badge); }
        const description = document.createElement('span'); description.className = 'description'; description.textContent = english ? project.descriptionEn : project.description;
        copy.append(kind, name, description);
        const arrow = document.createElement('span'); arrow.className = 'arrow'; arrow.setAttribute('aria-hidden','true'); arrow.textContent = '↗';
        link.append(mark, copy, arrow); list.append(link);
      }
      const dialog = root.querySelector('dialog');
      const trigger = root.querySelector('.trigger');
      trigger.addEventListener('click', () => dialog.showModal());
      root.querySelector('.close').addEventListener('click', () => dialog.close());
      dialog.addEventListener('close', () => trigger.focus({ preventScroll: true }));
      dialog.addEventListener('click', (event) => {
        if (event.target !== dialog) return;
        const r = dialog.getBoundingClientRect();
        if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) dialog.close();
      });
    }
  }
  if (!customElements.get('project-directory')) customElements.define('project-directory', ProjectDirectory);
})();
