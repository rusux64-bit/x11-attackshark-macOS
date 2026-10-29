// MouseSVG.swift
// Embedded copy of mouse-visualizer.svg (your svg.svg plus data-btn hooks, viewBox, and a gradient pair).
// Embedded so there is no Xcode "Target Membership" / bundle-resource step to get wrong.
// If you edit mouse-visualizer.svg, paste the new markup between the raw-string delimiters.

enum MouseSVG {
    static let markup = #"""
<svg class="mouse" width="520" height="1000" viewBox="0 0 520 1000" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg">
 <defs>
  <linearGradient id="scroll-up-fill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FF922E"/><stop offset="0.55" stop-color="#121214"/></linearGradient>
  <linearGradient id="scroll-down-fill" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#FF922E"/><stop offset="0.55" stop-color="#121214"/></linearGradient>
 </defs>

 <g>
  <title>Layer 1</title>
  <g id="body">
   <path stroke-width="1.5" stroke="#0a0a0a" fill="#17181b" d="m28,88l190,-76l74,0l190,76c8,6 11,42 11,82c0,150 1,300 5,420c5,110 7,190 -16,260c-37,95 -127,136 -227,136c-100,0 -190,-41 -227,-136c-23,-70 -21,-150 -16,-260c4,-120 5,-270 5,-420c0,-40 3,-76 11,-82z" id="body-shape"/>
   <path fill="#050505" d="m218,16l74,0l0,302l-33,24l-8,0l-33,-24l0,-302z" id="wheel-pocket"/>
  </g>
  <g id="buttons">
   <path stroke-width="1.5" stroke="#0a0a0a" fill="#2a2c31" d="m216,16l-184,76c-7,6 -9,38 -9,78c0,130 -1,230 2,278c2,30 9,42 25,42l201,0l0,-148l-35,-24l0,-302z" id="left-button" data-btn="left"/>
   <path stroke-width="1.5" stroke="#0a0a0a" fill="#2a2c31" d="m294,16l184,76c7,6 9,38 9,78c0,130 1,230 -2,278c-2,30 -9,42 -25,42l-201,0l0,-148l35,-24l0,-302z" id="right-button" data-btn="right"/>
   <path stroke-width="1.5" stroke="#0a0a0a" fill="#2a2c31" d="m27,346l-13,4c-7,2 -11,8 -11,18l0,80c0,12 5,19 24,22l0,-124z" id="side-forward" data-btn="forward"/>
   <path stroke-width="1.5" stroke="#0a0a0a" fill="#2a2c31" d="m28,502l-12,3c-7,2 -11,8 -11,18l0,75c0,12 5,19 23,22l0,-118z" id="side-back" data-btn="back"/>
  </g>
  <g id="wheel">
   <path stroke="#000" fill="#121214" d="m241,138l28,0c7.73,0 14,6.27 14,14l0,134c0,7.73 -6.27,14 -14,14l-28,0c-7.73,0 -14,-6.27 -14,-14l0,-134c0,-7.73 6.27,-14 14,-14z" id="wheel-body" class="wheel-body" data-btn="middle"/>
   <path stroke-width="1.6" stroke="#3d3f45" fill="none" d="m229,150l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0" id="wheel-ridges" class="ridges"/>
   <path fill="#e8e8e8" d="m228.2,142l0.2,0c0.66,0 1.2,0.54 1.2,1.2l0,151.6c0,0.66 -0.54,1.2 -1.2,1.2l-0.2,0c-0.66,0 -1.2,-0.54 -1.2,-1.2l0,-151.6c0,-0.66 0.54,-1.2 1.2,-1.2zm53.4,0l0.2,0c0.66,0 1.2,0.54 1.2,1.2l0,151.6c0,0.66 -0.54,1.2 -1.2,1.2l-0.2,0c-0.66,0 -1.2,-0.54 -1.2,-1.2l0,-151.6c0,-0.66 0.54,-1.2 1.2,-1.2z" id="wheel-edges"/>
  </g>
  <path fill="#22d3ee" d="m246,525l18,0c2.76,0 5,2.24 5,5l0,0c0,2.76 -2.24,5 -5,5l-18,0c-2.76,0 -5,-2.24 -5,-5l0,0c0,-2.76 2.24,-5 5,-5z" id="led"/>
  <rect stroke="#0a0a0a" id="svg_2" data-btn="left" height="38.22196" width="84.03329" y="307.55988" x="166.09148" stroke-dasharray="2,2" stroke-width="0" fill="#2a2c31"/>
  <path stroke="#0a0a0a" id="svg_3" data-btn="right" d="m260.0079,307.77656l84.03329,0l0,38.85089l-84.03329,0l0,-38.85089z" stroke-dasharray="2,2" stroke-width="0" fill="#2a2c31"/>
 </g>
</svg>
"""#

    static let markupLight = #"""
<svg class="mouse" width="520" height="1000" viewBox="0 0 520 1000" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg">

 <g>
  <title>Layer 1</title>
  <g id="body-light">
   <path stroke-width="1.5" stroke="#0a0a0a" fill="#ffffff" d="m28,89l190,-76l74,0l190,76c8,6 11,42 11,82c0,150 1,300 5,420c5,110 7,190 -16,260c-37,95 -127,136 -227,136c-100,0 -190,-41 -227,-136c-23,-70 -21,-150 -16,-260c4,-120 5,-270 5,-420c0,-40 3,-76 11,-82z" id="body-shape-light"/>
   <path fill="#ffffff" d="m218,17l74,0l0,302l-33,24l-8,0l-33,-24l0,-302z" id="wheel-pocket-light"/>
  </g>
  <g id="buttons-light">
   <path stroke-width="1.5" stroke="#0a0a0a" fill="#DDDDDD" d="m216,16l-184,76c-7,6 -9,38 -9,78c0,130 -1,230 2,278c2,30 9,42 25,42l201,0l0,-148l-35,-24l0,-302z" id="left-button-light" data-btn="left"/>
   <path stroke-width="1.5" stroke="#0a0a0a" fill="#DDDDDD" d="m294,16l184,76c7,6 9,38 9,78c0,130 1,230 -2,278c-2,30 -9,42 -25,42l-201,0l0,-148l35,-24l0,-302z" id="right-button-light" data-btn="right"/>
   <path stroke-width="1.5" stroke="#0a0a0a" fill="#DDDDDD" d="m27,346l-13,4c-7,2 -11,8 -11,18l0,80c0,12 5,19 24,22l0,-124z" id="side-forward-light" data-btn="forward"/>
   <path stroke-width="1.5" stroke="#0a0a0a" fill="#DDDDDD" d="m28,502l-12,3c-7,2 -11,8 -11,18l0,75c0,12 5,19 23,22l0,-118z" id="side-back-light" data-btn="back"/>
  </g>
  <g id="wheel-light">
   <path stroke="#000" fill="#121214" d="m241,138l28,0c7.73,0 14,6.27 14,14l0,134c0,7.73 -6.27,14 -14,14l-28,0c-7.73,0 -14,-6.27 -14,-14l0,-134c0,-7.73 6.27,-14 14,-14z" id="wheel-body-light" class="wheel-body" data-btn="middle"/>
   <path stroke-width="1.6" stroke="#3d3f45" fill="none" d="m229,150l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0m-52,9l52,0" id="wheel-ridges-light" class="ridges"/>
   <path fill="#e8e8e8" d="m228.2,142l0.2,0c0.66,0 1.2,0.54 1.2,1.2l0,151.6c0,0.66 -0.54,1.2 -1.2,1.2l-0.2,0c-0.66,0 -1.2,-0.54 -1.2,-1.2l0,-151.6c0,-0.66 0.54,-1.2 1.2,-1.2zm53.4,0l0.2,0c0.66,0 1.2,0.54 1.2,1.2l0,151.6c0,0.66 -0.54,1.2 -1.2,1.2l-0.2,0c-0.66,0 -1.2,-0.54 -1.2,-1.2l0,-151.6c0,-0.66 0.54,-1.2 1.2,-1.2z" id="wheel-edges-light"/>
  </g>
  <path fill="#22d3ee" d="m246,525l18,0c2.76,0 5,2.24 5,5l0,0c0,2.76 -2.24,5 -5,5l-18,0c-2.76,0 -5,-2.24 -5,-5l0,0c0,-2.76 2.24,-5 5,-5z" id="led-light"/>
  <rect id="svg_1-light" height="53" width="76.11767" y="-3" x="217.021" stroke-dasharray="2,2" stroke-width="0" fill="#ffffff"/>
  <rect stroke="#0a0a0a" id="svg_2-light" data-btn="left" height="38.22196" width="84.03329" y="307.55988" x="166.09148" stroke-dasharray="2,2" stroke-width="0" fill="#DDDDDD"/>
  <path stroke="#0a0a0a" id="svg_3-light" data-btn="right" d="m260.0079,307.77656l84.03329,0l0,38.85089l-84.03329,0l0,-38.85089z" stroke-dasharray="2,2" stroke-width="0" fill="#DDDDDD"/>
  <line fill="none" stroke="#0a0a0a" x1="216.5" y1="308.5" x2="251.5" y2="308.5" id="svg_6-light"/>
  <line fill="none" stroke="#0a0a0a" x1="294.5" y1="308.5" x2="260.5" y2="308.5" id="svg_7-light"/>
  <line stroke="#000" stroke-width="1.5" id="svg_4-light" y2="308.64474" x2="250.88596" y1="342.89474" x1="250.88596" fill="none"/>
  <line stroke="#000" id="svg_8-light" y2="308.625" x2="259.44737" y1="342.58333" x1="259.1" stroke-width="1.5" fill="none"/>
 </g>
</svg>
"""#
}
