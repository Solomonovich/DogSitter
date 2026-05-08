import re

file_path = "/Users/solofamily/Desktop/Walker/DogSitter/Sources/Views/BrowsePostsView.swift"

with open(file_path, "r") as f:
    content = f.read()

# 1. Update TabView
old_tabview = """                                TabView(selection: $selectedPostIndex) {
                                    ForEach(Array(sortedPosts.enumerated()), id: \\.element.id) { index, post in
                                        PostCardBanner(post: post)
                                            .padding(.horizontal)
                                            .tag(index)
                                            .onTapGesture {
                                                openPost(post)
                                            }
                                    }
                                }"""
new_tabview = """                                TabView(selection: $selectedPostIndex) {
                                    ForEach(Array(sortedPosts.enumerated()), id: \\.element.id) { index, post in
                                        VStack(spacing: 0) {
                                            PostCardBanner(post: post)
                                                .padding(.horizontal)
                                                .onTapGesture {
                                                    openPost(post)
                                                }
                                            Spacer()
                                        }
                                        .padding(.bottom, 83)
                                        .tag(index)
                                    }
                                }"""
content = content.replace(old_tabview, new_tabview)

# 2. Update ScrollView
old_scrollview = """                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    ForEach(sortedPosts) { post in
                                        PostCardBanner(post: post)
                                            .padding(.horizontal)
                                            .onTapGesture {
                                                openPost(post)
                                            }
                                    }
                                }
                                .padding(.bottom, 20)
                            }"""
new_scrollview = """                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    ForEach(sortedPosts) { post in
                                        PostCardBanner(post: post)
                                            .padding(.horizontal)
                                            .onTapGesture {
                                                openPost(post)
                                            }
                                    }
                                }
                                .padding(.bottom, 83)
                            }"""
content = content.replace(old_scrollview, new_scrollview)

# 3. Add .ignoresSafeArea(.all, edges: .bottom) to the outer VStack
# We look for:
#                 .offset(y: isShowingPostDetail ? max(0, detailDragOffset) : 0)
#             }
#         }
#         .onAppear {

old_outer_vstack_end = """                .offset(y: isShowingPostDetail ? max(0, detailDragOffset) : 0)
            }
        }
        .onAppear {"""

new_outer_vstack_end = """                .offset(y: isShowingPostDetail ? max(0, detailDragOffset) : 0)
            }
            .ignoresSafeArea(.all, edges: .bottom)
        }
        .onAppear {"""

content = content.replace(old_outer_vstack_end, new_outer_vstack_end)

with open(file_path, "w") as f:
    f.write(content)

print("Applied bottom sheet fixes")
