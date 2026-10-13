import React from "react";

interface Props {
  className?: string;
}

export default function BrandExtensionIcon({ className = "h-8 w-8" }: Props) {
  return (
    <div className={`overflow-hidden rounded-xl ${className}`}>
      <svg className="h-full w-full" viewBox="0 0 100 100" aria-hidden="true">
        <defs>
          <linearGradient id="lumenpass-extension-gradient" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#3B3E44" />
            <stop offset="1" stopColor="#2D3035" />
          </linearGradient>
        </defs>
        <rect width="100" height="100" rx="21" fill="url(#lumenpass-extension-gradient)" />
        <circle cx="50" cy="50" r="33" fill="#AFAFAF" />
        <circle cx="50" cy="50" r="27" fill="#CE2C26" />
        <rect x="47.2" y="46.5" width="5.6" height="21.5" rx="2.8" fill="#D8D8D8" />
        <rect x="52.8" y="55" width="6.4" height="3.5" rx="1.75" fill="#D8D8D8" />
        <rect x="52.8" y="62.5" width="6.4" height="3.5" rx="1.75" fill="#D8D8D8" />
        <circle cx="50" cy="40.5" r="9.5" fill="#D8D8D8" />
        <circle cx="50" cy="40.5" r="4" fill="#CE2C26" />
      </svg>
    </div>
  );
}
