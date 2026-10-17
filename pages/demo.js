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

// Cathedral 3D Stage Gallery Controller
(function initCathedralGallery() {
  const stage = document.querySelector('#gallery-stage');
  const indicatorsContainer = document.querySelector('#gallery-indicators');
  const categoryBtns = document.querySelectorAll('.category-btn');
  const prevBtn = document.querySelector('.stage-prev');
  const nextBtn = document.querySelector('.stage-next');
  const captionBadge = document.querySelector('#caption-badge');
  const captionTitle = document.querySelector('#caption-title');
  const captionDesc = document.querySelector('#caption-desc');
  const lightbox = document.querySelector('#gallery-lightbox');
  const lightboxImg = document.querySelector('#lightbox-img');
  const lightboxTitle = document.querySelector('#lightbox-title');
  const lightboxClose = document.querySelector('.lightbox-close');

  if (!stage || !indicatorsContainer) return;

  const english = document.documentElement.lang === 'en';

  const galleryDataZh = {
    settings: [
      {
        title: '设备连接',
        badge: '多设备管理',
        windowTitle: '设备连接 · Voice Input Buddy',
        src: 'assets/screenshots/connection-zh.png',
        alt: 'Voice Input Buddy 设备连接界面：小米与 Google G9N9N 遥控器卡片、连接状态、电量显示与麦克风独立增益滑块',
        desc: '管理所有已配对的蓝牙遥控器（如小米遥控器、Google G9N9N），实时查看连接状态与电池电量；支持单独调节并保存每台遥控器的麦克风输入增益（0 dB 至 20 dB）。'
      },
      {
        title: '按键映射',
        badge: '核心按键映射',
        windowTitle: '按键映射 · Voice Input Buddy',
        src: 'assets/screenshots/mapping-zh.png',
        alt: 'Voice Input Buddy 按键映射设置界面：可视化遥控器按键映射，支持单击、双击、长按与自定义快捷键',
        desc: '中央显示遥控器按键示意图，支持为电源键、确定键、方向键、返回键、主页键、菜单键与 TV 键分别指定单击、双击和长按动作，可绑定系统操作、自定义快捷键或常用语。'
      },
      {
        title: '常用语编辑',
        badge: '常用语库管理',
        windowTitle: '常用语调整 · Voice Input Buddy',
        src: 'assets/screenshots/phrases-zh.png',
        alt: 'Voice Input Buddy 常用语调整界面：遥控器五键分配、常用语库与短语编辑管理',
        desc: '按键映射内置常用语面板管理，可为圆盘方向键与 OK 键自定义短语列表，支持中英文短语编辑、词库导入导出与五键灵活分配，高频语句一键即发。'
      },
      {
        title: '输入法集成',
        badge: '语音工具',
        windowTitle: '输入法与语音工具集成 · Voice Input Buddy',
        src: 'assets/screenshots/integration-zh.png',
        alt: 'Voice Input Buddy 输入法与语音工具集成界面：微信输入法、豆包输入法、网易叭哥说、Typeless、VoiceCursor 等配置入口',
        desc: '提供微信输入法、豆包输入法、网易叭哥说、Typeless、VoiceCursor 及其他自定义工具的专用配置向导入口，并可自由选择语音触发按键（Fn、Command、Option 等）与长按/点按模式。'
      },
      {
        title: '权限与驱动',
        badge: '环境检测',
        windowTitle: '权限与环境 · Voice Input Buddy',
        src: 'assets/screenshots/permissions-zh.png',
        alt: 'Voice Input Buddy 权限与环境界面：蓝牙、输入监控、辅助功能权限与虚拟麦克风驱动状态',
        desc: '集中核对蓝牙、输入监控与辅助功能三项系统授权，自动监控 Voice Input Buddy Mic 虚拟麦克风驱动的加载状态，并附带直观的驱动安装与重启引导。'
      },
      {
        title: '关于与更新',
        badge: '版本与更新',
        windowTitle: '关于与设置 · Voice Input Buddy',
        src: 'assets/screenshots/about-zh.png',
        alt: 'Voice Input Buddy 关于与设置界面：应用版本信息、自动检查更新、发布说明与通用卸载器',
        desc: '查看当前 App 版本与架构（Apple 芯片 / Intel），支持通过 Sparkle 自动或手动检查更新并查看更新日志；提供开源许可证信息与通用卸载工具入口。'
      }
    ],
    wizard: [
      {
        title: '第 1 步 · 系统权限',
        badge: '向导 · 环境检测',
        windowTitle: '系统权限 · 首次使用向导',
        src: 'assets/screenshots/wizard-permissions-zh.png',
        alt: '首次使用向导：系统权限检查，一键引导开启蓝牙、输入监控与辅助功能权限',
        desc: '首次打开应用时，向导逐项引导授权蓝牙、输入监控和辅助功能，确保遥控器正常通信与按键发送；左下角可随时切换中文或英文。'
      },
      {
        title: '第 2 步 · 设备类型',
        badge: '向导 · 设备准备',
        windowTitle: '设备类型 · 首次使用向导',
        src: 'assets/screenshots/wizard-source-zh.png',
        alt: '首次使用向导：选择控制设备类型，支持实体遥控器（小米、Google G9N9N 等）或手机输入伴侣',
        desc: '选择你使用的硬件设备：支持小米蓝牙遥控器、Google G9N9N、Apple Siri Remote 等实体遥控器，或通过扫码使用手机作为控制与语音输入伴侣。'
      },
      {
        title: '第 3 步 · 连接遥控器',
        badge: '向导 · 蓝牙配对',
        windowTitle: '连接遥控器 · 首次使用向导',
        src: 'assets/screenshots/wizard-remote-zh.png',
        alt: '首次使用向导：连接遥控器步骤，图解配对按键与实时连接检测',
        desc: '图文图解小米及兼容遥控器的蓝牙配对按键组合（长按 TV 键或 Home+Menu 键），靠近电脑自动发现并建立蓝牙通道。'
      },
      {
        title: '第 4 步 · 按键测试',
        badge: '向导 · 按键反馈',
        windowTitle: '按键测试 · 首次使用向导',
        src: 'assets/screenshots/wizard-controls-zh.png',
        alt: '首次使用向导：按键测试步骤，实时亮起圆盘方向键与功能键',
        desc: '在遥控器上按下方向键或确定键，屏幕对应按键实时高亮响应，快速确认 Mac 已成功接收实体按键，避免按键占用冲突。'
      },
      {
        title: '第 5 步 · 驱动检测',
        badge: '向导 · 声卡检查',
        windowTitle: '驱动检查 · 首次使用向导',
        src: 'assets/screenshots/wizard-driver-zh.png',
        alt: '首次使用向导：虚拟麦克风驱动检测，自动配置 Voice Input Buddy Mic',
        desc: '自动检测并配置随安装包安装的 Voice Input Buddy Mic 虚拟声卡驱动，固定音频输出路径，无需手动调整系统声音设备。'
      },
      {
        title: '第 6 步 · 输入工具',
        badge: '向导 · 工具匹配',
        windowTitle: '输入工具 · 首次使用向导',
        src: 'assets/screenshots/wizard-tool-zh.png',
        alt: '首次使用向导：输入工具选择与设置指引，包含微信输入法、豆包等操作步骤',
        desc: '选择你喜爱的输入法或听写工具，向导右侧分步骤提供截屏指引：从输入法麦克风选择到语音快捷键设置，轻松完成对接。'
      },
      {
        title: '第 7 步 · 试说与校准',
        badge: '向导 · 录音测试',
        windowTitle: '语音测试 · 首次使用向导',
        src: 'assets/screenshots/wizard-test-zh.png',
        alt: '首次使用向导：语音测试与麦克风增益，按住说话实时显示识别文字与音量增益',
        desc: '按住遥控器语音键说出第一句话，实时查看语音接收与文本输入效果；若音量偏小可当场微调遥控器麦克风增益，确认无误后完成向导。'
      }
    ]
  };

  const galleryDataEn = {
    settings: [
      {
        title: 'Devices',
        badge: 'Multi-device',
        windowTitle: 'Devices · Voice Input Buddy',
        src: 'assets/screenshots/connection-en.png',
        alt: 'Voice Input Buddy Devices interface: Xiaomi and Google G9N9N remote cards, connection status, battery levels, and independent microphone gain sliders',
        desc: 'Manage connected Bluetooth remotes (Xiaomi, Google G9N9N), check live battery percentages and charging states, and adjust individual microphone gain (0 dB to 20 dB).'
      },
      {
        title: 'Button Mapping',
        badge: 'Core Mapping',
        windowTitle: 'Button Mapping · Voice Input Buddy',
        src: 'assets/screenshots/mapping-en.png',
        alt: 'Voice Input Buddy Button Mapping interface: visual remote layout mapping single, double, and long press shortcuts',
        desc: 'The central remote diagram shows each physical button, supporting single-press, double-press, and long-press shortcuts for Power, OK, Navigation, Back, Home, Menu, and TV keys.'
      },
      {
        title: 'Common Phrases',
        badge: 'Phrase Editor',
        windowTitle: 'Common Phrases · Voice Input Buddy',
        src: 'assets/screenshots/phrases-en.png',
        alt: 'Voice Input Buddy Common Phrases interface: 5-way directional pad assignment and custom phrase library editor',
        desc: 'Edit common phrase libraries inside button mapping. Assign custom phrases to directional buttons and OK button for instant text insertion, with backup import/export.'
      },
      {
        title: 'Voice Tools',
        badge: 'Integrations',
        windowTitle: 'Voice Tools Integration · Voice Input Buddy',
        src: 'assets/screenshots/integration-en.png',
        alt: 'Voice Input Buddy Voice Tools interface: setup guides for WeType, Doubao, NetEase Bageshuo, Typeless, VoiceCursor, and custom shortcuts',
        desc: 'Guided setup for WeType, Doubao, NetEase Bageshuo, Typeless, VoiceCursor, and custom tools, with flexible trigger key options (Fn/Globe, Command, Option).'
      },
      {
        title: 'Permissions & Driver',
        badge: 'System Environment',
        windowTitle: 'Permissions & Driver · Voice Input Buddy',
        src: 'assets/screenshots/permissions-en.png',
        alt: 'Voice Input Buddy Permissions interface: Bluetooth, Input Monitoring, Accessibility permissions and virtual microphone driver status',
        desc: 'Centralized overview of Bluetooth, Input Monitoring, and Accessibility permissions, along with the status and instructions for the Voice Input Buddy Mic driver.'
      },
      {
        title: 'About & Updates',
        badge: 'Version & Updates',
        windowTitle: 'About & Settings · Voice Input Buddy',
        src: 'assets/screenshots/about-en.png',
        alt: 'Voice Input Buddy About interface: application version, Sparkle automatic updates, release notes, and universal uninstaller',
        desc: 'Check app version and architecture (Apple silicon / Intel), manage automatic Sparkle updates, inspect release notes, and access the uninstaller.'
      }
    ],
    wizard: [
      {
        title: 'Step 1 · Permissions',
        badge: 'Wizard · System Check',
        windowTitle: 'System Permissions · Setup Wizard',
        src: 'assets/screenshots/wizard-permissions-en.png',
        alt: 'Setup Wizard: System permissions check for Bluetooth, Input Monitoring, and Accessibility',
        desc: 'Step-by-step guidance to authorize Bluetooth, Input Monitoring, and Accessibility permissions, ensuring reliable communication and key posting.'
      },
      {
        title: 'Step 2 · Device Type',
        badge: 'Wizard · Device Choice',
        windowTitle: 'Control Source · Setup Wizard',
        src: 'assets/screenshots/wizard-source-en.png',
        alt: 'Setup Wizard: Select control hardware, supporting physical remotes (Xiaomi, Google G9N9N) or phone companion',
        desc: 'Select your preferred control hardware: physical remotes such as Xiaomi, Google G9N9N, Apple Siri Remote, or a mobile phone companion via QR code.'
      },
      {
        title: 'Step 3 · Connect Remote',
        badge: 'Wizard · Pairing',
        windowTitle: 'Connect Remote · Setup Wizard',
        src: 'assets/screenshots/wizard-remote-en.png',
        alt: 'Setup Wizard: Remote pairing illustration and live connection status check',
        desc: 'Illustrated instructions for Bluetooth pairing key combinations on Xiaomi and compatible remotes, discovering and pairing automatically.'
      },
      {
        title: 'Step 4 · Button Test',
        badge: 'Wizard · Button Check',
        windowTitle: 'Button Test · Setup Wizard',
        src: 'assets/screenshots/wizard-controls-en.png',
        alt: 'Setup Wizard: Control button test step showing live feedback on directional buttons',
        desc: 'Press directional or OK buttons on the remote to see corresponding highlights on screen, confirming physical button delivery without key remapper conflicts.'
      },
      {
        title: 'Step 5 · Driver Check',
        badge: 'Wizard · Audio Ready',
        windowTitle: 'Driver Check · Setup Wizard',
        src: 'assets/screenshots/wizard-driver-en.png',
        alt: 'Setup Wizard: Virtual microphone driver detection for Voice Input Buddy Mic',
        desc: 'Automatically checks and routes audio through the bundled Voice Input Buddy Mic driver, locking in dedicated virtual microphone output.'
      },
      {
        title: 'Step 6 · Voice Tool',
        badge: 'Wizard · Tool Setup',
        windowTitle: 'Input Tool · Setup Wizard',
        src: 'assets/screenshots/wizard-tool-en.png',
        alt: 'Setup Wizard: Voice input tool selection with visual setup guides',
        desc: 'Choose your preferred input method or dictation tool, with step-by-step screenshots guiding microphone selection and voice shortcut keys.'
      },
      {
        title: 'Step 7 · Voice Test & Gain',
        badge: 'Wizard · Speech Test',
        windowTitle: 'Voice Test · Setup Wizard',
        src: 'assets/screenshots/wizard-test-en.png',
        alt: 'Setup Wizard: First-phrase voice test with live transcription and microphone gain adjustment',
        desc: 'Hold the voice button and speak your first test sentence. Adjust remote microphone gain in real time if needed before completing setup.'
      }
    ]
  };

  const galleryData = english ? galleryDataEn : galleryDataZh;
  let currentTrack = 'settings';
  let currentIndex = 0;

  function renderTrack(trackKey, startIndex) {
    currentTrack = trackKey;
    const items = galleryData[trackKey] || [];
    currentIndex = Math.max(0, Math.min(startIndex || 0, items.length - 1));

    stage.innerHTML = '';
    indicatorsContainer.innerHTML = '';

    items.forEach((item, index) => {
      const slide = document.createElement('div');
      slide.className = 'stage-slide';
      slide.setAttribute('role', 'group');
      slide.setAttribute('aria-label', `${item.title} (${index + 1}/${items.length})`);
      slide.dataset.index = index;

      slide.innerHTML = `
        <div class="window-top" aria-hidden="true">
          <div class="window-dots"><i></i><i></i><i></i></div>
          <span class="window-title">${item.windowTitle}</span>
        </div>
        <img src="${item.src}" alt="${item.alt}" width="1020" height="772" loading="${index === 0 ? 'eager' : 'lazy'}">
      `;

      slide.addEventListener('click', () => {
        if (index === currentIndex) {
          openLightbox(item);
        } else {
          goToIndex(index);
        }
      });

      stage.appendChild(slide);

      const ind = document.createElement('button');
      ind.className = 'gallery-indicator-btn' + (index === currentIndex ? ' is-active' : '');
      ind.type = 'button';
      ind.innerHTML = `<span class="indicator-step">${index + 1}</span><span>${item.title}</span>`;
      ind.addEventListener('click', () => goToIndex(index));
      indicatorsContainer.appendChild(ind);
    });

    updateStage();
  }

  function updateStage() {
    const slides = stage.querySelectorAll('.stage-slide');
    const indicators = indicatorsContainer.querySelectorAll('.gallery-indicator-btn');
    const items = galleryData[currentTrack] || [];
    const currentItem = items[currentIndex];

    slides.forEach((slide, index) => {
      slide.classList.remove('slide-active', 'slide-prev', 'slide-next', 'slide-hidden-left', 'slide-hidden-right');
      const diff = index - currentIndex;
      if (diff === 0) {
        slide.classList.add('slide-active');
        slide.setAttribute('tabindex', '0');
      } else if (diff === -1) {
        slide.classList.add('slide-prev');
        slide.setAttribute('tabindex', '-1');
      } else if (diff === 1) {
        slide.classList.add('slide-next');
        slide.setAttribute('tabindex', '-1');
      } else if (diff < -1) {
        slide.classList.add('slide-hidden-left');
        slide.setAttribute('tabindex', '-1');
      } else {
        slide.classList.add('slide-hidden-right');
        slide.setAttribute('tabindex', '-1');
      }
    });

    indicators.forEach((ind, index) => {
      ind.classList.toggle('is-active', index === currentIndex);
      ind.setAttribute('aria-selected', index === currentIndex ? 'true' : 'false');
    });

    if (currentItem) {
      if (captionBadge) captionBadge.textContent = currentItem.badge;
      if (captionTitle) captionTitle.textContent = currentItem.title;
      if (captionDesc) captionDesc.textContent = currentItem.desc;
    }
  }

  function goToIndex(newIndex) {
    const items = galleryData[currentTrack] || [];
    if (!items.length) return;
    currentIndex = (newIndex + items.length) % items.length;
    updateStage();
  }

  function openLightbox(item) {
    if (!lightbox || !lightboxImg) return;
    lightboxImg.src = item.src;
    lightboxImg.alt = item.alt;
    if (lightboxTitle) lightboxTitle.textContent = item.windowTitle;
    if (typeof lightbox.showModal === 'function') {
      lightbox.showModal();
    }
  }

  function closeLightbox() {
    if (!lightbox) return;
    if (typeof lightbox.close === 'function') {
      lightbox.close();
    }
  }

  if (prevBtn) prevBtn.addEventListener('click', () => goToIndex(currentIndex - 1));
  if (nextBtn) nextBtn.addEventListener('click', () => goToIndex(currentIndex + 1));

  categoryBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      categoryBtns.forEach(b => b.classList.remove('is-active'));
      btn.classList.add('is-active');
      renderTrack(btn.dataset.track, 0);
    });
  });

  if (lightboxClose) lightboxClose.addEventListener('click', closeLightbox);
  if (lightbox) {
    lightbox.addEventListener('click', event => {
      if (event.target === lightbox) closeLightbox();
    });
  }

  stage.addEventListener('keydown', event => {
    if (event.key === 'ArrowLeft') {
      event.preventDefault();
      goToIndex(currentIndex - 1);
    } else if (event.key === 'ArrowRight') {
      event.preventDefault();
      goToIndex(currentIndex + 1);
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      const currentItem = (galleryData[currentTrack] || [])[currentIndex];
      if (currentItem) openLightbox(currentItem);
    }
  });

  let touchStartX = 0;
  stage.addEventListener('touchstart', event => {
    touchStartX = event.changedTouches[0].screenX;
  }, { passive: true });
  stage.addEventListener('touchend', event => {
    const diff = event.changedTouches[0].screenX - touchStartX;
    if (Math.abs(diff) > 40) {
      if (diff > 0) goToIndex(currentIndex - 1);
      else goToIndex(currentIndex + 1);
    }
  }, { passive: true });

  renderTrack('settings', 0);
})();


