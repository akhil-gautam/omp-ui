/** The line icons the interface uses. */

import type { ReactNode } from "react";

type IconProps = {
	size?: number;
	className?: string;
};

const Svg = ({
	size = 16,
	className,
	children,
}: IconProps & { children: ReactNode }) => (
	<svg
		width={size}
		height={size}
		viewBox="0 0 24 24"
		fill="none"
		stroke="currentColor"
		strokeWidth="1.6"
		strokeLinecap="round"
		strokeLinejoin="round"
		className={className}
		aria-hidden="true"
	>
		{children}
	</svg>
);

export const IconPanel = (props: IconProps) => (
	<Svg {...props}>
		<rect x="3" y="4" width="18" height="16" rx="2.5" />
		<path d="M9.5 4v16" />
	</Svg>
);

export const IconPlus = (props: IconProps) => (
	<Svg {...props}>
		<path d="M12 5v14M5 12h14" />
	</Svg>
);

export const IconFilter = (props: IconProps) => (
	<Svg {...props}>
		<path d="M4 6h16l-6 7v5l-4 2v-7z" />
	</Svg>
);

export const IconSearch = (props: IconProps) => (
	<Svg {...props}>
		<circle cx="11" cy="11" r="6.5" />
		<path d="m16 16 4 4" />
	</Svg>
);

export const IconMore = (props: IconProps) => (
	<Svg {...props}>
		<circle cx="6" cy="12" r="1.4" fill="currentColor" />
		<circle cx="12" cy="12" r="1.4" fill="currentColor" />
		<circle cx="18" cy="12" r="1.4" fill="currentColor" />
	</Svg>
);

export const IconChevronDown = (props: IconProps) => (
	<Svg {...props}>
		<path d="m6 9 6 6 6-6" />
	</Svg>
);

export const IconChevronRight = (props: IconProps) => (
	<Svg {...props}>
		<path d="m9 6 6 6-6 6" />
	</Svg>
);

export const IconChevronLeft = (props: IconProps) => (
	<Svg {...props}>
		<path d="m15 6-6 6 6 6" />
	</Svg>
);

export const IconFolder = (props: IconProps) => (
	<Svg {...props}>
		<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h3l2 2.5h8A2.5 2.5 0 0 1 21 10v7.5a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z" />
	</Svg>
);

export const IconGitBranch = (props: IconProps) => (
	<Svg {...props}>
		<circle cx="7" cy="5.5" r="2.2" />
		<circle cx="7" cy="18.5" r="2.2" />
		<circle cx="17" cy="9" r="2.2" />
		<path d="M7 7.7v8.6M9.2 9H17" />
	</Svg>
);

export const IconMessage = (props: IconProps) => (
	<Svg {...props}>
		<path d="M20 14.5a2.5 2.5 0 0 1-2.5 2.5H8l-4 3.5V6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5z" />
	</Svg>
);

export const IconBolt = (props: IconProps) => (
	<Svg {...props}>
		<path d="M13 3 5 13.5h6L11 21l8-10.5h-6z" />
	</Svg>
);

export const IconPlan = (props: IconProps) => (
	<Svg {...props}>
		<path d="M4 7h10M4 12h16M4 17h7" />
		<path d="M17 5.5 19 7.5 17 9.5" />
	</Svg>
);

export const IconHome = (props: IconProps) => (
	<Svg {...props}>
		<path d="m4 11 8-6.5 8 6.5" />
		<path d="M6.5 9.5V19h11V9.5" />
	</Svg>
);

export const IconPlug = (props: IconProps) => (
	<Svg {...props}>
		<path d="M9 3v5M15 3v5" />
		<path d="M6.5 8h11v3a5.5 5.5 0 0 1-11 0z" />
		<path d="M12 16.5V21" />
	</Svg>
);

export const IconServer = (props: IconProps) => (
	<Svg {...props}>
		<rect x="3.5" y="4.5" width="17" height="6" rx="1.8" />
		<rect x="3.5" y="13.5" width="17" height="6" rx="1.8" />
		<path d="M7 7.5h.01M7 16.5h.01" />
	</Svg>
);

export const IconBook = (props: IconProps) => (
	<Svg {...props}>
		<path d="M4 5.5A1.5 1.5 0 0 1 5.5 4H10a2 2 0 0 1 2 2v13a2 2 0 0 0-2-2H5.5A1.5 1.5 0 0 1 4 15.5z" />
		<path d="M20 5.5A1.5 1.5 0 0 0 18.5 4H14a2 2 0 0 0-2 2v13a2 2 0 0 1 2-2h4.5a1.5 1.5 0 0 0 1.5-1.5z" />
	</Svg>
);

export const IconFile = (props: IconProps) => (
	<Svg {...props}>
		<path d="M13.5 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8.5z" />
		<path d="M13.5 3v5.5H19" />
	</Svg>
);

export const IconUsers = (props: IconProps) => (
	<Svg {...props}>
		<circle cx="9" cy="8" r="3" />
		<path d="M3.5 19.5a5.5 5.5 0 0 1 11 0" />
		<path d="M16 5.5a3 3 0 0 1 0 5M17 14.5a5.5 5.5 0 0 1 3.5 5" />
	</Svg>
);

export const IconWrench = (props: IconProps) => (
	<Svg {...props}>
		<path d="M15.5 3.5a5 5 0 0 0-6.6 6.6L3.5 15.5a2 2 0 0 0 2.8 2.8l5.4-5.4a5 5 0 0 0 6.6-6.6L15.5 9 13 6.5z" />
	</Svg>
);

export const IconArrowUp = (props: IconProps) => (
	<Svg {...props}>
		<path d="M12 19V5M6 11l6-6 6 6" />
	</Svg>
);

export const IconMic = (props: IconProps) => (
	<Svg {...props}>
		<rect x="9" y="3" width="6" height="11" rx="3" />
		<path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3" />
	</Svg>
);

export const IconGear = (props: IconProps) => (
	<Svg {...props}>
		<circle cx="12" cy="12" r="3" />
		<path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.2 5.2l2.1 2.1M16.7 16.7l2.1 2.1M18.8 5.2l-2.1 2.1M7.3 16.7l-2.1 2.1" />
	</Svg>
);

export const IconSun = (props: IconProps) => (
	<Svg {...props}>
		<circle cx="12" cy="12" r="4" />
		<path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.2 5.2l1.4 1.4M17.4 17.4l1.4 1.4M18.8 5.2l-1.4 1.4M6.6 17.4l-1.4 1.4" />
	</Svg>
);

export const IconMoon = (props: IconProps) => (
	<Svg {...props}>
		<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5z" />
	</Svg>
);

export const IconPlay = (props: IconProps) => (
	<Svg {...props}>
		<path d="M7 4.5 19 12 7 19.5z" />
	</Svg>
);

export const IconStop = (props: IconProps) => (
	<Svg {...props}>
		<rect x="6" y="6" width="12" height="12" rx="2" />
	</Svg>
);

export const IconCommand = (props: IconProps) => (
	<Svg {...props}>
		<path d="M8 4.5a2 2 0 1 0-2 2h12a2 2 0 1 0-2-2v15a2 2 0 1 0 2-2H6a2 2 0 1 0 2 2z" />
	</Svg>
);
