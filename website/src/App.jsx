import { useRef, useState } from "react";

const repository = "https://github.com/gofenix/Hasp";
const release = `${repository}/releases/tag/v0.1.0`;
const download = `${repository}/releases/download/v0.1.0/Hasp-0.1.0-universal.zip`;
const asset = (name) => `/assets/${name}`;
const demos = [
  { id: "overview", label: "一处掌握", title: "常用操作，一处掌握。", description: "点开菜单栏，切换外观、声音输出和设备连接。", alt: "Hasp 浅色面板，展示外观、声音输出和键盘鼠标电量" },
  { id: "audio", label: "声音输出", title: "换副耳机，声音跟上。", description: "选择已配对的蓝牙耳机，连接后直接切换声音输出。", alt: "Hasp 声音输出面板，AirPods Pro 显示为正在使用" },
  { id: "appearance", label: "自动外观", title: "白天浅色，入夜深色。", description: "按设定时间或当地日出日落，自动切换深浅外观。", alt: "Hasp 深色面板，外观选择自动模式" },
  { id: "fold", label: "菜单栏折叠", title: "常用的留下，其余收起。", description: "收起不常用的菜单栏图标，需要时再打开原生菜单。", alt: "Hasp 折叠面板，列出 Wi-Fi、声音和电池状态项" },
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
      <DownloadLink className="nav-download">下载 Mac 版</DownloadLink>
    </header>
    <main id="main" className="page">
      <section className="hero" aria-labelledby="hero-title">
        <div className="hero-brand"><img src={asset("hasp-icon.png")} width="88" height="88" alt="" /><span>Hasp</span></div>
        <h1 id="hero-title">常用控制，收进菜单栏。</h1>
        <p className="hero-description">切换耳机，查看设备电量，调整深浅外观。<br className="desktop-break" />常用操作，在菜单栏里一处掌握。</p>
        <div className="hero-actions"><DownloadLink /><a className="button secondary" href={repository}>GitHub</a></div>
        <p className="compatibility">macOS 26.0 及以上<span>·</span>Apple Silicon 与 Intel<span>·</span>v0.1.0</p>
      </section>
      <section id="demo" className="showcase" aria-label="Hasp 功能预览">
        <div className={`desktop-stage stage-${demo.id}`} role="tabpanel" id="demo-panel" aria-labelledby={`tab-${demo.id}`} tabIndex="0">
          <img className="stage-wallpaper" src={asset("paper-desktop.webp")} width="1852" height="849" alt="" fetchPriority="high" />
          <div className="stage-note" aria-hidden="true"><span className="stage-kicker">YOUR MAC, AT HAND</span><p>常用操作，<br />尽在手边。</p><span className="stage-hairline" /></div>
          <div className="panel-stack">{demos.map((item, index) => <img key={item.id} className={`app-panel ${index === active ? "visible" : ""}`} src={asset(`panel-${item.id}.png`)} width="640" height="1000" alt={item.alt} aria-hidden={index !== active} />)}</div>
          <span className="render-note">Hasp 实际界面 · 演示设备数据</span>
        </div>
        <div className="gallery-footer">
          <div className="gallery-caption" aria-live="polite"><h2>{demo.title}</h2><p>{demo.description}</p></div>
          <div className="gallery-tabs" role="tablist" aria-label="选择功能预览" onKeyDown={navigateTabs}>{demos.map((item, index) => <button key={item.id} id={`tab-${item.id}`} role="tab" type="button" aria-selected={index === active} aria-controls="demo-panel" tabIndex={index === active ? 0 : -1} ref={(element) => { tabs.current[index] = element; }} onClick={() => setActive(index)}>{item.label}</button>)}</div>
        </div>
      </section>
      <section className="features section" id="features" aria-labelledby="features-title">
        <div className="section-intro"><p className="eyebrow">常用功能</p><h2 id="features-title">少开几个设置窗口。</h2><p>声音输出、设备连接、外观切换与菜单栏整理，<br className="desktop-break" />点开 Hasp，就能操作。</p></div>
        <dl className="feature-list">
          <div><dt><span>01</span>声音，随你切换</dt><dd>在 Mac 扬声器和耳机之间切换。选择已配对的蓝牙耳机，连接后直接设为声音输出。</dd></div>
          <div><dt><span>02</span>设备，一目了然</dt><dd>查看键盘、鼠标和触控板的连接状态与可用电量。连接或断开设备，都在同一个面板完成。</dd></div>
          <div><dt><span>03</span>外观，顺应时间</dt><dd>随时切换浅色或深色外观，也可以设定时段，或跟随当地日出日落自动调整。</dd></div>
          <div><dt><span>04</span>菜单栏，收放自如</dt><dd>收起不常用的图标，需要时访问原生菜单。离开 Mac 前，还能从面板一键锁屏。</dd></div>
        </dl>
      </section>
      <section className="start section" id="start" aria-labelledby="start-title">
        <div className="section-intro"><p className="eyebrow">从这里开始</p><h2 id="start-title">从菜单栏，开始使用。</h2><p>下载后完成设置，让常用控制随时可用。</p></div>
        <ol className="steps">
          <li><span className="step-number">1</span><h3>下载 Hasp</h3><p>阅读版本与安装说明，下载安装包，解压后将 Hasp 拖入“应用程序”。</p><a href={release}>查看版本与安装说明</a></li>
          <li><span className="step-number">2</span><h3>按需开启权限</h3><p>打开设置中的权限页，根据需要启用外观切换、蓝牙和菜单栏折叠。</p><a href="#questions">了解权限用途</a></li>
          <li><span className="step-number">3</span><h3>点开菜单栏</h3><p>点击 Hasp 图标，切换声音输出、查看设备状态，或调整深浅外观。</p><a href="#demo" onClick={() => setActive(0)}>查看面板</a></li>
        </ol>
        <p className="preview-notice">安装包已使用 Developer ID 签名，尚未完成 Apple 公证。首次打开前请阅读 <a href={release}>Release 说明</a>。</p>
      </section>
      <section className="questions section" id="questions" aria-labelledby="questions-title">
        <div className="section-intro"><p className="eyebrow">常见问题</p><h2 id="questions-title">你可能想知道。</h2></div>
        <div className="faq-list">
          <details><summary>支持我的 Mac 吗？</summary><p>需要 macOS 26.0 或更高版本，支持 Apple Silicon 和 Intel Mac。当前已在 macOS 26.6.2 上完成构建与只读检查；macOS 27 的菜单栏折叠尚待实机验证。</p></details>
          <details><summary>为什么需要这些权限？</summary><p>蓝牙权限用于连接已配对的设备，外观切换需要控制“系统事件”，菜单栏折叠需要辅助功能权限。日出日落模式可选用定位；macOS 27 的折叠还需要读取菜单栏配置。各项用途都会在权限页说明，由你按需开启。</p></details>
          <details><summary>需要麦克风或屏幕录制权限吗？</summary><p>不需要。Hasp 切换声音输出时不使用麦克风，也不录制屏幕。查看权限状态不会自动请求授权。</p></details>
          <details><summary>在哪里下载和反馈问题？</summary><p>安装包和版本说明均可在 <a href={release}>GitHub Release</a> 查看。遇到问题可以到 <a href={`${repository}/issues`}>Issues</a> 反馈。附上诊断信息前，请先去除设备名等私人信息。</p></details>
        </div>
      </section>
      <section className="closing section"><img src={asset("hasp-icon.png")} width="64" height="64" alt="" /><h2>让常用控制，随时在手。</h2><p>声音、设备、外观与菜单栏，一个面板就能掌握。</p><DownloadLink /><a className="release-link" href={release}>v0.1.0 · 查看更新</a></section>
    </main>
    <footer className="footer"><div className="footer-brand"><span>Hasp</span><p>Mac 常用控制，一处掌握。</p></div><div className="footer-links"><a href={repository}>GitHub</a><a href={release}>版本记录</a><a href="https://kami.tw93.fun/index-zh.html">Design with Kami</a></div></footer>
  </>;
}
