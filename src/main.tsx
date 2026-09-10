import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import CustomerActivation from './CustomerActivation';
import AppErrorBoundary from './AppErrorBoundary';
import './offline.css';
import './accessibility.css';
import './product-excellence.css';
import './aghbari-premium.css';
import './aghbari-operations.css';
import './aghbari-command-center.css';

const inviteToken = new URLSearchParams(window.location.search).get('invite');
const entry = inviteToken ? <CustomerActivation token={inviteToken} /> : <App />;

createRoot(document.getElementById('root')!).render(
  <StrictMode><AppErrorBoundary>{entry}</AppErrorBoundary></StrictMode>
);

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js').catch(() => undefined));
}
