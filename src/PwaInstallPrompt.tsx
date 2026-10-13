import { useEffect, useState } from 'react';

type InstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
};

export default function PwaInstallPrompt() {
  const [installEvent, setInstallEvent] = useState<InstallPromptEvent | null>(null);
  const [dismissed, setDismissed] = useState(false);
  const [showIosHelp, setShowIosHelp] = useState(false);

  useEffect(() => {
    const standalone = window.matchMedia('(display-mode: standalone)').matches ||
      (navigator as Navigator & { standalone?: boolean }).standalone === true;
    if (standalone) return;

    const onBeforeInstall = (event: Event) => {
      event.preventDefault();
      setInstallEvent(event as InstallPromptEvent);
    };
    const onInstalled = () => {
      setInstallEvent(null);
      setDismissed(true);
    };
    window.addEventListener('beforeinstallprompt', onBeforeInstall);
    window.addEventListener('appinstalled', onInstalled);
    const isIos = /iphone|ipad|ipod/i.test(navigator.userAgent);
    if (isIos) setShowIosHelp(true);
    return () => {
      window.removeEventListener('beforeinstallprompt', onBeforeInstall);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, []);

  if (dismissed || (!installEvent && !showIosHelp)) return null;

  const install = async () => {
    if (!installEvent) return;
    await installEvent.prompt();
    const choice = await installEvent.userChoice;
    if (choice.outcome === 'accepted') setDismissed(true);
    setInstallEvent(null);
  };

  return (
    <aside className="pwa-install-card" dir="rtl" aria-label="تثبيت تطبيق وين نلقاو">
      <div className="pwa-install-copy">
        <strong>ثبّت وين نلقاو على تليفونك</strong>
        <span>{installEvent ? 'افتح التطبيق من الشاشة الرئيسية وقت ما تحب.' : 'في Safari اضغط مشاركة ثم Add to Home Screen.'}</span>
      </div>
      {installEvent ? <button type="button" onClick={install}>تثبيت</button> : null}
      <button className="pwa-dismiss" type="button" aria-label="إغلاق" onClick={() => setDismissed(true)}>×</button>
    </aside>
  );
}
