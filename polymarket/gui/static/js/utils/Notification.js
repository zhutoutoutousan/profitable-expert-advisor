/**
 * Notification Utility
 * Global notification system
 */

export class Notification {
    static show(message, type = 'info') {
        console.log(`[${type.toUpperCase()}] ${message}`);
        
        const notification = document.createElement('div');
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 15px 25px;
            background: rgba(0, 255, 255, 0.1);
            border: 2px solid var(--neon-cyan);
            color: var(--neon-cyan);
            font-family: 'Orbitron', sans-serif;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.1em;
            z-index: 10000;
            box-shadow: 0 0 20px var(--neon-cyan);
            animation: slideIn 0.3s ease;
        `;
        notification.textContent = message;
        
        document.body.appendChild(notification);
        
        setTimeout(() => {
            notification.style.animation = 'slideOut 0.3s ease';
            setTimeout(() => notification.remove(), 300);
        }, 3000);
    }
}

// Make it globally available
window.showNotification = Notification.show;
