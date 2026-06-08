import React from "react";

interface Props {
  className?: string;
}

export default function BrandExtensionIcon({ className = "h-8 w-8" }: Props) {
  return (
    <div className={`flex items-center justify-center rounded-xl bg-brand-600 ${className}`}>
      <svg
        className="h-[58%] w-[58%]"
        viewBox="0 0 24 24"
        fill="none"
        stroke="white"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <path d="M7.5 10V7.75a4.5 4.5 0 1 1 9 0V10" />
        <rect x="5.5" y="10" width="13" height="9" rx="2.5" />
      </svg>
    </div>
  );
}
