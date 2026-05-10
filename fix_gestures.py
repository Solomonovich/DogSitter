import re

file_path = "/Users/solofamily/Desktop/Walker/DogSitter/Sources/Views/BrowsePostsView.swift"
with open(file_path, "r") as f:
    content = f.read()

# 1. Add startingSheetHeight state
state_block = """    @State private var sheetHeight: CGFloat = 400
    @State private var previousSheetHeight: CGFloat = 400
    @State private var detailDragOffset: CGFloat = 0"""
new_state_block = """    @State private var sheetHeight: CGFloat = 400
    @State private var previousSheetHeight: CGFloat = 400
    @State private var detailDragOffset: CGFloat = 0
    @State private var dragStartHeight: CGFloat = 400"""
content = content.replace(state_block, new_state_block)

# 2. Fix the Capsule drag handle
# Replace the Capsule() block with a VStack wrapper and global gesture
old_capsule_block = """                        Capsule()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 40, height: 5)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        sheetHeight = max(collapsedHeight, min(expandedHeight, sheetHeight - value.translation.height))
                                    }
                                    .onEnded { value in
                                        let velocity = -value.velocity.height
                                        let midpoint = (collapsedHeight + expandedHeight) / 2
                                        
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            if velocity > 300 || sheetHeight > midpoint {
                                                sheetHeight = expandedHeight
                                            } else if velocity < -300 || sheetHeight < midpoint {
                                                sheetHeight = collapsedHeight
                                            } else {
                                                if sheetHeight > midpoint {
                                                    sheetHeight = expandedHeight
                                                } else {
                                                    sheetHeight = collapsedHeight
                                                }
                                            }
                                        }
                                    }
                            )"""

new_capsule_block = """                        VStack {
                            Capsule()
                                .fill(Color.gray.opacity(0.5))
                                .frame(width: 40, height: 5)
                                .padding(.top, 8)
                                .padding(.bottom, 10)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    if dragStartHeight == 0 { dragStartHeight = sheetHeight }
                                    sheetHeight = max(collapsedHeight, min(expandedHeight, dragStartHeight - value.translation.height))
                                }
                                .onEnded { value in
                                    dragStartHeight = 0
                                    let velocity = -value.velocity.height
                                    let midpoint = (collapsedHeight + expandedHeight) / 2
                                    
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        if velocity > 300 || sheetHeight > midpoint {
                                            sheetHeight = expandedHeight
                                        } else if velocity < -300 || sheetHeight < midpoint {
                                            sheetHeight = collapsedHeight
                                        } else {
                                            if sheetHeight > midpoint {
                                                sheetHeight = expandedHeight
                                            } else {
                                                sheetHeight = collapsedHeight
                                            }
                                        }
                                    }
                                }
                        )"""
content = content.replace(old_capsule_block, new_capsule_block)

# 3. Fix the Detail View Drag Gesture
old_detail_gesture = """                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if value.translation.height > 0 {
                                        detailDragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    let velocity = value.velocity.height
                                    if detailDragOffset > 100 || velocity > 300 {
                                        detailDragOffset = 0
                                        closePost()
                                    } else {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            detailDragOffset = 0
                                        }
                                    }
                                }
                        )"""

new_detail_gesture = """                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    if value.translation.height > 0 {
                                        detailDragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    let velocity = value.velocity.height
                                    if detailDragOffset > 100 || velocity > 300 {
                                        detailDragOffset = 0
                                        closePost()
                                    } else {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            detailDragOffset = 0
                                        }
                                    }
                                }
                        )"""
content = content.replace(old_detail_gesture, new_detail_gesture)

# Also fix the dragStartHeight initialization issue onAppear
# We don't strictly need to do it onAppear since it sets to sheetHeight dynamically, but let's be clean.
# No need, setting to 0 works perfectly.

with open(file_path, "w") as f:
    f.write(content)

print("Applied gesture fixes")
