import { useRef, useState } from "react";

const repository = "https://github.com/gofenix/Hasp";
const release = `${repository}/releases/tag/v0.1.0-preview.1`;
const download = `${repository}/releases/download/v0.1.0-preview.1/Hasp-0.1.0-preview.1-universal.zip`;
const asset = (name) => `/assets/${name}`;
const demos = [
  { id: "overview", label: "一处掌握", title: "常用的，都在这里。", description: "外观、声音、蓝牙设备，点开菜单栏就能找到。", alt: "Hasp 浅色面板，展示外观、声音输出和键盘鼠标电量" },
  { id: "audio", label: "声音输出", title: "从扬声器，到耳机。", description: "选一副耳机，连接和切换输出一并完成。", alt: "Hasp 声音输出面板，AirPods Pro 显示为正在使用" },
  { id: "appearance", label: "自动外观", title: "天色变了，外观也变。", description: "浅色、深色随手切换，也可以交给定时或日出日落。", alt: "Hasp 深色面板，外观选择自动模式" },
  { id: "fold", label: "菜单栏折叠", title: "留一点，清爽的空间。", description: "收起不常用的状态项，需要时再点开。", alt: "Hasp 折叠面板，列出 Wi-Fi、声音和电池状态项" },
];
function DownloadLink({ children = "下载 Mac 版", className = "button primary" }) {
  return <a className={className} href={download}>{children}</a>;
}
export function App() {
  const [active, setActive] = useState(0);
  const [menuOpen, setMenuOpen] = useState(false);
  const tabs = useRef([]);
  const demo = demos[active];
  function navigateTabs(event) {
    const offsets = { ArrowRight: 1, ArrowLeft: -1 };
    let next;
    if (event.key in offsets) next = (active + offsets[event.key] + demos.length) % demos.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = demos.length - 1;
    else return;
    event.preventDefault(); setActive(next); tabs.current[next]?.focus();
  }
  return <>
    <a className="skip-link" href="#main">跳到正文</a>
    <header className="navigation">
      <a className="nav-brand" href="#" aria-label="Hasp 首页"><img src={asset("hasp-icon.png")} width="30" height="30" alt="" /><span>Hasp</span></a>
      <button className="menu-toggle" type="button" aria-expanded={menuOpen} aria-controls="nav-links" onClick={() => setMenuOpen(!menuOpen)}>{menuOpen ? "收起" : "菜单"}</button>
      <nav id="nav-links" aria-label="主导航" className={menuOpen ? "nav-links open" : "nav-links"} onClick={() => setMenuOpen(false)}><a href="#features">功能</a><a href="#start">使用指南</a><a href={release}>更新日志</a><a href={repository}>GitHub</a></nav>
      <DownloadLink className="nav-download">下载预览版</DownloadLink>
    </header>
    <main id="main" className="page">
      <section className="hero" aria-labelledby="hero-title">
        <div className="hero-brand"><img src={asset("hasp-icon.png")} width="88" height="88" alt="" /><span>Hasp</span></div>
        <h1 id="hero-title">常用控制，收进菜单栏。</h1>
        <p className="hero-description">切换声音输出、连接蓝牙设备、自动调整外观。<br className="desktop-break" />顺手整理菜单栏，让每一次点击都简单一点。</p>
        <div className="hero-actions"><DownloadLink /><a className="button secondary" href="#demo">看看它怎么用</a></div>
        <p className="compatibility">macOS 26.0 及以上<span>·</span>Apple Silicon 与 Intel<span>·</span>预览版</p>
      </section>
      <section id="demo" className="showcase" aria-label="Hasp 功能预览">
        <div className={`desktop-stage stage-${demo.id}`} role="tabpanel" id="demo-panel" aria-labelledby={`tab-${demo.id}`} tabIndex="0">
          <img className="stage-wallpaper" src={asset("paper-desktop.webp")} width="1852" height="849" alt="" fetchPriority="high" />
          <div className="stage-note" aria-hidden="true"><span className="stage-kicker">A LITTLE LESS FRICTION</span><p>顺手一点，<br />专心一点。</p><span className="stage-hairline" /></div>
          <div className="panel-stack">{demos.map((item, index) => <img key={item.id} className={`app-panel ${index === active ? "visible" : ""}`} src={asset(`panel-${item.id}.png`)} width="640" height="1000" alt={item.alt} aria-hidden={index !== active} />)}</div>
          <span className="render-note">Hasp 实际界面 · 演示设备数据</span>
        </div>
        <div className="gallery-footer">
          <div className="gallery-caption" aria-live="polite"><h2>{demo.title}</h2><p>{demo.description}</p></div>
          <div className="gallery-tabs" role="tablist" aria-label="选择功能预览" onKeyDown={navigateTabs}>{demos.map((item, index) => <button key={item.id} id={`tab-${item.id}`} role="tab" type="button" aria-selected={index === active} aria-controls="demo-panel" tabIndex={index === active ? 0 : -1} ref={(element) => { tabs.current[index] = element; }} onClick={() => setActive(index)}>{item.label}</button>)}</div>
        </div>
      </section>
      <section className="features section" id="features" aria-labelledby="features-title">
        <div className="section-intro"><p className="eyebrow">留在手边的小事</p><h2 id="features-title">少开几个设置窗口。</h2><p>不用打断手上的事。那些一天要用好几次的操作，<br className="desktop-break" />在菜单栏里，随时等你。</p></div>
        <dl className="feature-list">
          <div><dt><span>01</span>声音，随你切换</dt><dd>在 Mac 扬声器和耳机之间切换。已配对的蓝牙耳机也在这里，连接后直接设为声音输出。</dd></div>
          <div><dt><span>02</span>设备，一目了然</dt><dd>查看键盘、鼠标和触控板的连接状态，以及设备提供的电量信息。连接、断开，都不用另开窗口。</dd></div>
          <div><dt><span>03</span>外观，顺应时间</dt><dd>浅色、深色一键切换。选择固定时间、自定义时段，或按当地日出日落自动调整。</dd></div>
          <div><dt><span>04</span>菜单栏，留白一点</dt><dd>把暂时用不到的图标收起来，需要时再访问原生菜单。面板里的锁屏按钮，也让离开更方便。</dd></div>
        </dl>
      </section>
      <section className="start section" id="start" aria-labelledby="start-title">
        <div className="section-intro"><p className="eyebrow">从这里开始</p><h2 id="start-title">装好，点开，就熟悉了。</h2><p>原生 Mac 小工具，照着你的习惯来。</p></div>
        <ol className="steps">
          <li><span className="step-number">1</span><h3>下载 Hasp</h3><p>从 GitHub Release 下载通用版本，解压后将 Hasp 拖入“应用程序”。</p><a href={release}>查看版本与安装说明</a></li>
          <li><span className="step-number">2</span><h3>按需开启权限</h3><p>在设置的权限页选择要用的能力。自动外观、蓝牙和菜单栏折叠各有对应说明。</p><a href="#questions">了解权限用途</a></li>
          <li><span className="step-number">3</span><h3>让小事更顺手</h3><p>点开菜单栏里的 Hasp，把耳机、外观和设备控制放到伸手可及的地方。</p><a href="#demo" onClick={() => setActive(0)}>再看一眼面板</a></li>
        </ol>
        <p className="preview-notice">当前为早期预览版，尚未完成 Apple 公证。安装前请阅读 <a href={release}>Release 说明</a>。</p>
      </section>
      <section className="questions section" id="questions" aria-labelledby="questions-title">
        <div className="section-intro"><p className="eyebrow">你可能想知道</p><h2 id="questions-title">几个小问题。</h2></div>
        <div className="faq-list">
          <details><summary>支持我的 Mac 吗？</summary><p>需要 macOS 26.0 或更高版本，提供 Apple Silicon 与 Intel 通用安装包。当前在 macOS 26.6.2 上完成构建与只读诊断；macOS 27 的折叠后端保留自动化测试，尚待实机验收。</p></details>
          <details><summary>为什么需要这些权限？</summary><p>蓝牙权限用于相关设备功能；自动切换外观需要控制“系统事件”；列出并操作其他应用的菜单栏项目需要辅助功能权限。日出日落模式可选用定位。macOS 27 的原生折叠还需要读取菜单栏配置。权限页会逐项说明，由你主动开启。</p></details>
          <details><summary>需要麦克风或屏幕录制权限吗？</summary><p>不需要。声音输出切换不使用麦克风，也不需要录制屏幕。检查权限状态不会自动发起授权请求。</p></details>
          <details><summary>在哪里下载和反馈问题？</summary><p>安装包和版本说明都放在 <a href={release}>GitHub Release</a>。遇到问题可以到 <a href={`${repository}/issues`}>Issues</a> 留言；请先去除诊断中的设备名等私人信息。</p></details>
        </div>
      </section>
      <section className="closing section"><img src={asset("hasp-icon.png")} width="64" height="64" alt="" /><h2>小小一个，顺手许多。</h2><p>把日常小事交给 Hasp，继续你正在做的事。</p><DownloadLink /><a className="release-link" href={release}>v0.1.0-preview.1 · 查看更新</a></section>
    </main>
    <footer className="footer"><div className="footer-brand"><span>Hasp</span><p>为 Mac 的日常小事而做。</p></div><div className="footer-links"><a href={repository}>GitHub</a><a href={release}>版本记录</a><a href="https://kami.tw93.fun/index-zh.html">Design with Kami</a></div></footer>
  </>;
}
