import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import PwaInstallPrompt from './PwaInstallPrompt';
import './styles.css';

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((error) => {
      console.error('Win Nalkaw service worker registration failed:', error);
    });
  });
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
    <PwaInstallPrompt />
  </React.StrictMode>
);
