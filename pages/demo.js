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
