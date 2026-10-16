// Local illustration only: no microphone, network requests or text collection.
const button = document.querySelector('#talk');
const art = document.querySelector('.hero-art');
const status = document.querySelector('#demo-status');
const english = document.documentElement.lang === 'en';
function start() { art.classList.add('is-listening'); status.textContent = english ? 'Button held · Sending audio' : '语音键按下 · 传递声音'; }
function stop() { art.classList.remove('is-listening'); status.textContent = english ? 'Button released · Over to your tool' : '语音键松开 · 交给输入工具'; }
button.addEventListener('pointerdown', event => { button.setPointerCapture(event.pointerId); start(); });
button.addEventListener('pointerup', stop);
button.addEventListener('pointercancel', stop);
button.addEventListener('lostpointercapture', stop);
button.addEventListener('keydown', event => { if (event.key === ' ' || event.key === 'Enter') { event.preventDefault(); start(); } });
button.addEventListener('keyup', event => { if (event.key === ' ' || event.key === 'Enter') stop(); });
button.addEventListener('blur', stop);

// App interface tabs switching
const interfaceTabs = document.querySelectorAll('.interface-tab');
const interfacePanels = document.querySelectorAll('.interface-panel');
const windowTitle = document.querySelector('#interface-window-title');

const titlesZh = {
  'panel-mapping': '按键映射 · Voice Input Buddy',
  'panel-connection': '设备连接 · Voice Input Buddy',
  'panel-integration': '输入法与语音工具集成 · Voice Input Buddy',
  'panel-phrases': '常用语管理 · Voice Input Buddy',
  'panel-permissions': '权限与环境 · Voice Input Buddy'
};

const titlesEn = {
  'panel-mapping': 'Button Mapping · Voice Input Buddy',
  'panel-connection': 'Devices · Voice Input Buddy',
  'panel-integration': 'Voice Tools Integration · Voice Input Buddy',
  'panel-phrases': 'Common Phrases · Voice Input Buddy',
  'panel-permissions': 'Permissions & Driver · Voice Input Buddy'
};

interfaceTabs.forEach(tab => {
  tab.addEventListener('click', () => {
    const targetPanelId = tab.dataset.panel;
    interfaceTabs.forEach(t => {
      t.classList.remove('is-active');
      t.setAttribute('aria-selected', 'false');
    });
    interfacePanels.forEach(p => {
      p.hidden = true;
      p.classList.remove('is-active');
    });
    tab.classList.add('is-active');
    tab.setAttribute('aria-selected', 'true');
    const panel = document.getElementById(targetPanelId);
    if (panel) {
      panel.hidden = false;
      panel.classList.add('is-active');
    }
    if (windowTitle) {
      const titles = english ? titlesEn : titlesZh;
      windowTitle.textContent = titles[targetPanelId] || 'Voice Input Buddy';
    }
  });

  tab.addEventListener('keydown', event => {
    const tabList = Array.from(interfaceTabs);
    const index = tabList.indexOf(tab);
    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
      event.preventDefault();
      const next = tabList[(index + 1) % tabList.length];
      next.focus();
      next.click();
    } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
      event.preventDefault();
      const prev = tabList[(index - 1 + tabList.length) % tabList.length];
      prev.focus();
      prev.click();
    }
  });
});

